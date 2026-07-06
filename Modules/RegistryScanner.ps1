<#
.SYNOPSIS
    Módulo de Varredura e Limpeza do Registro do Windows.
.DESCRIPTION
    Escaneia categorias objetivamente seguras do registro (entradas de
    desinstalação órfãs, SharedDLLs quebradas, App Paths inexistentes,
    MUICache obsoleto, Run/RunOnce órfãos, Fontes não instaladas,
    Extensões de shell não registradas) e permite limpeza com backup
    automático da chave afetada antes de qualquer exclusão.
    NÃO mexe em CLSID/COM, ProgIDs de extensão de arquivo ou hives de
    sistema (SAM/SECURITY/SYSTEM bruto) - essas categorias são as que
    mais quebram instalações em limpadores genéricos e foram
    deliberadamente deixadas de fora.
#>

. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\SecurityHelper.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\Logger.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\ConfigManager.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\Winapp2Parser.ps1"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# ---------------------------------------------------------------------------
# Carregar lista de exclusão a partir de Settings.json (chave RegistryExclude)
# ---------------------------------------------------------------------------
$cfg = Get-WMSConfig
$global:RegistryExclude = @()
if ($cfg.RegistryExclude) { $global:RegistryExclude = $cfg.RegistryExclude }

function Test-ExcludedPath {
    param([string]$Path)
    foreach ($ex in $global:RegistryExclude) {
        if ($Path -like $ex) { return $true }
    }
    return $false
}

# ---------------------------------------------------------------------------
# Definição das categorias seguras de varredura
# ---------------------------------------------------------------------------

function Get-RegistryScanCategories {
    $baseCategories = @(
        @{
            Name = "Entradas de Desinstalação Órfãs"
            Hives = @(
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
                "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
                "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
            )
            Check = {
                param($key)
                $props = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
                if (-not $props) { return $false }
                $pathToCheck = $null
                if ($props.InstallLocation) { $pathToCheck = $props.InstallLocation }
                elseif ($props.UninstallString) {
                    $exe = ($props.UninstallString -replace '"', '') -split ' ' | Select-Object -First 1
                    $pathToCheck = $exe
                }
                if (-not $pathToCheck) { return $false }
                return (-not (Test-Path -Path $pathToCheck -ErrorAction SilentlyContinue))
            }
        },
        @{
            Name = "SharedDLLs Quebradas"
            Hives = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\SharedDLLs")
            IsValueScan = $true
            Check = {
                param($valuePath)
                return (-not (Test-Path -Path $valuePath -ErrorAction SilentlyContinue))
            }
        },
        @{
            Name = "App Paths Quebrados"
            Hives = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths")
            Check = {
                param($key)
                $default = (Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue).'(default)'
                if (-not $default) { return $false }
                return (-not (Test-Path -Path $default -ErrorAction SilentlyContinue))
            }
        },
        @{
            Name = "MUICache Obsoleto"
            Hives = @("HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache")
            IsValueScan = $true
            ValueNameIsPath = $true
            Check = {
                param($valuePath)
                $clean = $valuePath -replace '\.FriendlyAppName$', '' -replace '\.ApplicationCompany$', ''
                return (-not (Test-Path -Path $clean -ErrorAction SilentlyContinue))
            }
        },
        @{
            Name = "Run / RunOnce Órfãos"
            Hives = @(
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
                "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
                "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
            )
            IsValueScan = $true
            Check = {
                param($valuePath)
                if ([string]::IsNullOrWhiteSpace($valuePath)) { return $false }
                $cmd = $valuePath.Trim()
                if ($cmd.StartsWith('"')) { $cmd = $cmd.TrimStart('"'); $cmd = $cmd.Substring(0,$cmd.IndexOf('"')) }
                else { $cmd = $cmd.Split(' ')[0] }
                return (-not (Test-Path -Path $cmd -ErrorAction SilentlyContinue))
            }
        },
        @{
            Name = "Fontes Não Instaladas"
            Hives = @("HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts")
            IsValueScan = $true
            Check = {
                param($fontFile)
                $fontsDir = [Environment]::GetFolderPath('Fonts')
                $full = Join-Path $fontsDir $fontFile
                return (-not (Test-Path -Path $full -ErrorAction SilentlyContinue))
            }
        },
        @{
            Name = "Extensões de Shell Órfãs (ShellEx)"
            Hives = @(
                "HKLM:\SOFTWARE\Classes\*\ShellEx",
                "HKLM:\SOFTWARE\Classes\Directory\ShellEx",
                "HKLM:\SOFTWARE\Classes\Drive\ShellEx"
            )
            Check = {
                param($key)
                $clsid = (Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue).'(default)'
                if (-not $clsid) { return $false }
                $clsidPath = "HKCR:\CLSID\$clsid"
                return (-not (Test-Path -Path $clsidPath -ErrorAction SilentlyContinue))
            }
        }
    )

    # Opcional: carregar regras Winapp2.ini
    $cfg = Get-WMSConfig
    if ($cfg.UseWinapp2) {
        try {
            $winapp2Rules = Import-Winapp2Rules
            if ($winapp2Rules.Count -gt 0) {
                Write-Host "  [INFO] Adicionando $($winapp2Rules.Count) regras Winapp2..." -ForegroundColor Cyan
                $baseCategories += $winapp2Rules
            }
        } catch {
            Write-Host "  [AVISO] Falha ao importar Winapp2: $_" -ForegroundColor Yellow
        }
    }

return $baseCategories
}

# ---------------------------------------------------------------------------
# Varredura (somente leitura, com barra de progresso em tempo real)
# ---------------------------------------------------------------------------

function Get-RegistryJunkReport {
    param(
        [switch]$UseDotNet = $true
    )
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  VARREDURA DO REGISTRO" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $categories = Get-RegistryScanCategories
    $findings = [System.Collections.Generic.List[Object]]::new()
    $totalCategories = $categories.Count
    $catIndex = 0

    foreach ($cat in $categories) {
        $catIndex++
        $baseActivity = "Varrendo registro"
        Write-Progress -Activity $baseActivity -Status "$($cat.Name)..." -PercentComplete ([int](($catIndex - 1) / $totalCategories * 100))

        foreach ($hivePath in $cat.Hives) {
            if (-not (Test-Path $hivePath -ErrorAction SilentlyContinue)) { continue }
            if (Test-ExcludedPath -Path $hivePath) { continue }

            if ($cat.IsValueScan) {
                try {
                    $props = Get-ItemProperty -Path $hivePath -ErrorAction SilentlyContinue
                    if (-not $props) { continue }
                    $valueNames = $props.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" }
                    $total = ($valueNames | Measure-Object).Count
                    $i = 0
                    foreach ($v in $valueNames) {
                        $i++
                        if ($total -gt 0) {
                            $pct = [int]([Math]::Round((($catIndex - 1) / $totalCategories) * 100 + ($i / $total) * (100 / $totalCategories)))
                            Write-Progress -Activity $baseActivity -Status "$($cat.Name): $($v.Name)" -PercentComplete $pct
                        }
                        $checkTarget = if ($cat.ValueNameIsPath) { $v.Name } else { $v.Value }
                        if ([string]::IsNullOrWhiteSpace($checkTarget)) { continue }
                        if (Test-ExcludedPath -Path "$hivePath\$($v.Name)") { continue }
                        try {
                            if (& $cat.Check $checkTarget) {
                                $findings.Add([PSCustomObject]@{
                                    Category  = $cat.Name
                                    KeyPath   = $hivePath
                                    ValueName = $v.Name
                                    Detail    = $checkTarget
                                })
                            }
                        } catch { continue }
                    }
                } catch { continue }
            } else {
                try {
                    $subKeys = Get-ChildItem -Path $hivePath -ErrorAction SilentlyContinue
                    $total = ($subKeys | Measure-Object).Count
                    $i = 0
                    foreach ($key in $subKeys) {
                        $i++
                        if ($total -gt 0) {
                            $pct = [int](($catIndex - 1) / $totalCategories * 100 + ($i / $total) * (100 / $totalCategories))
                            Write-Progress -Activity $baseActivity -Status "$($cat.Name): $($key.PSChildName)" -PercentComplete $pct
                        }
                        $fullPath = $key.PSPath
                        if (Test-ExcludedPath -Path $fullPath) { continue }
                        try {
                            if (& $cat.Check $key) {
                                $findings.Add([PSCustomObject]@{
                                    Category  = $cat.Name
                                    KeyPath   = ($key.PSPath -replace '^Microsoft\.PowerShell\.Core\\Registry::', '')
                                    ValueName = $null
                                    Detail    = $key.PSChildName
                                })
                            }
                        } catch { continue }
                    }
                } catch { continue }
            }
        }
    }

    Write-Progress -Activity "Varrendo registro" -Completed
    Write-Log "Varredura de registro concluída: $($findings.Count) itens órfãos encontrados." "INFO"
    return $findings
}

function Show-RegistryJunkReport {
    param($Findings)

    if ($Findings.Count -eq 0) {
        Write-Host "`n      [OK] Nenhuma chave órfã encontrada nas categorias seguras verificadas." -ForegroundColor Green
        return
    }

    Write-Host "`n      $($Findings.Count) item(ns) órfão(s) encontrado(s):" -ForegroundColor Yellow
    $grouped = $Findings | Group-Object Category
    foreach ($group in $grouped) {
        Write-Host "`n      -- $($group.Name) ($($group.Count)) --" -ForegroundColor Cyan
        $group.Group | Select-Object -First 15 | ForEach-Object {
            $label = if ($_.ValueName) { "$($_.KeyPath)\$($_.ValueName)" } else { $_.KeyPath }
            Write-Host "        $label" -ForegroundColor White
        }
        if ($group.Count -gt 15) {
            Write-Host "        ... e mais $($group.Count - 15) item(ns)." -ForegroundColor DarkGray
        }
    }
}

# ---------------------------------------------------------------------------
# Backup pontual da(s) chave(s) afetadas antes da limpeza
# ---------------------------------------------------------------------------

function Backup-RegistryFindings {
    param($Findings)

    $backupPath = Get-SafeBackupPath
    if (-not (Test-Path $backupPath)) {
        New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupFile = Join-Path -Path $backupPath -ChildPath "RegistryScanBackup_$timestamp.reg"

    $uniqueRoots = $Findings | Select-Object -ExpandProperty KeyPath -Unique | ForEach-Object {
        ($_ -replace '^HKEY_CURRENT_USER', 'HKCU:' -replace '^HKEY_LOCAL_MACHINE', 'HKLM:')
    } | Select-Object -Unique

    $exported = 0
    foreach ($root in $uniqueRoots) {
        try {
            $regRoot = $root -replace '^HKLM:', 'HKLM' -replace '^HKCU:', 'HKCU'
            $safeName = Convert-PathToSafeFileName -Path $root
            $individualFile = Join-Path -Path $backupPath -ChildPath "RegScan_$timestamp`_$safeName.reg"
            $proc = Start-Process -FilePath "reg.exe" -ArgumentList "export `"$regRoot`" `"$individualFile`" /y" -Wait -PassThru -NoNewWindow -ErrorAction SilentlyContinue
            if ($proc.ExitCode -eq 0) { $exported++ }
        } catch { continue }
    }

    Write-Host "      [OK] Backup de $exported chave(s) salvo em: $backupPath" -ForegroundColor Green
    Write-Log "Backup pontual de $exported chaves de registro antes da limpeza." "SUCCESS"
    return $exported -gt 0
}

# ---------------------------------------------------------------------------
# Limpeza (com backup obrigatório + barra de progresso)
# ---------------------------------------------------------------------------

function Clear-RegistryJunk {
    param(
        $Findings,
        [switch]$DryRun
    )

    if ($Findings.Count -eq 0) { return }

    if ($DryRun) {
        Write-Host "`n[DRY-RUN] Simulação de limpeza - nenhuma alteração será feita." -ForegroundColor Yellow
    } else {
        Write-Host "`n[>] Fazendo backup das chaves afetadas antes de excluir..." -ForegroundColor Yellow
        $backupOk = Backup-RegistryFindings -Findings $Findings
        if (-not $backupOk) {
            Write-Host "      [ERRO] Backup falhou. Abortando limpeza por segurança." -ForegroundColor Red
            Write-Log "Limpeza de registro abortada: backup falhou." "ERROR"
            return
        }
    }

    $total = $Findings.Count
    $i = 0
    $removed = 0
    $failed = 0
    $undoLog = @()

    foreach ($item in $Findings) {
        $i++
        Write-Progress -Activity "Limpando registro" -Status "$($item.Category): $($item.Detail)" -PercentComplete [int]($i / $total * 100)
        try {
            if ($item.ValueName) {
                if (-not $DryRun) {
                    Remove-ItemProperty -Path $item.KeyPath -Name $item.ValueName -Force -ErrorAction Stop
                }
                $undoLog += "Remove-ItemProperty -Path '$($item.KeyPath)' -Name '$($item.ValueName)'"
            } else {
                if (-not $DryRun) {
                    Remove-Item -Path $item.KeyPath -Recurse -Force -ErrorAction Stop
                }
                $undoLog += "Remove-Item -Path '$($item.KeyPath)' -Recurse -Force"
            }
            $removed++
        } catch {
            $failed++
            Write-Log "Falha ao remover $($item.KeyPath) ($($item.ValueName)): $_" "WARNING"
        }
    }
    Write-Progress -Activity "Limpando registro" -Completed

    if (-not $DryRun) {
        $backupPath = Get-SafeBackupPath
        $undoFile = Join-Path $backupPath "Undo_RegistryCleanup_$(Get-Date -Format 'yyyyMMdd_HHmmss').ps1"
        $undoLog | Set-Content -Path $undoFile -Encoding UTF8
        Write-Host "      [OK] Script de desfazer salvo em: $undoFile" -ForegroundColor Green
    }

    Write-Host "`n      [OK] $removed chave(s)/valor(es) removido(s). $failed falha(s)." -ForegroundColor Green
    Write-Log "Limpeza de registro: $removed removidos, $failed falhas." "SUCCESS"
}

# ---------------------------------------------------------------------------
# Menu
# ---------------------------------------------------------------------------

function Invoke-RegistryScan {
    param(
        [switch]$DryRun
    )
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  VARREDURA E LIMPEZA DO REGISTRO" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Categorias verificadas: Uninstall órfãs, SharedDLLs quebradas," -ForegroundColor DarkGray
    Write-Host "  App Paths quebrados, MUICache obsoleto, Run/RunOnce órfãos," -ForegroundColor DarkGray
    Write-Host "  Fontes não instaladas, Extensões Shell órfãs. Nada de CLSID/COM/hives" -ForegroundColor DarkGray
    Write-Host "  de sistema - essas ficam de fora por segurança." -ForegroundColor DarkGray
    Write-Host "`n  1. Apenas Varrer (relatório, nada é alterado)"
    Write-Host "  2. Varrer e Limpar (com backup automático + confirmação)"
    if ($DryRun) { Write-Host "  3. Modo Simulação (Dry-Run) - mostra o que seria removido" }
    Write-Host "  4. Voltar ao Menu Principal"
    Write-Host "`n========================================" -ForegroundColor Cyan

    $choice = Read-Host "Digite o número da sua escolha"
    $choice = $choice -replace '\s+', ''

    $maxOpt = if ($DryRun) { 3 } else { 4 }
    if (-not (Test-ValidNumericInput -Value $choice -Min 1 -Max $maxOpt)) {
        Write-Host "Opção inválida." -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }

    if ($choice -eq "4" -or ($choice -eq "3" -and -not $DryRun)) { return }

    $findings = Get-RegistryJunkReport
    Show-RegistryJunkReport -Findings $findings

    if ($choice -eq "1") { return }

    if ($choice -eq "2" -and $findings.Count -gt 0) {
        $confirm = Read-Host "`nConfirmar a exclusão dos $($findings.Count) item(ns) acima? Um backup será feito antes. (S/N)"
        if ($confirm -match '^[Ss]') {
            Clear-RegistryJunk -Findings $findings
        } else {
            Write-Host "      Limpeza cancelada pelo usuário." -ForegroundColor Yellow
            Write-Log "Limpeza de registro cancelada pelo usuário após revisão do relatório." "INFO"
        }
    } elseif ($choice -eq "3" -and $DryRun -and $findings.Count -gt 0) {
        Write-Host "`n[DRY-RUN] Itens que seriam removidos:" -ForegroundColor Yellow
        Clear-RegistryJunk -Findings $findings -DryRun
    }
}
