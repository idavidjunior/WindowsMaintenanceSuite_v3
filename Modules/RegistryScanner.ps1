<#
.SYNOPSIS
    Modulo de Varredura e Limpeza do Registro do Windows.
.DESCRIPTION
    Escaneia categorias objetivamente seguras do registro (entradas de
    desinstalacao orfas, SharedDLLs quebradas, App Paths inexistentes e
    MUICache obsoleto) e permite limpeza com backup automatico da chave
    afetada antes de qualquer exclusao. NAO mexe em CLSID/COM, ProgIDs de
    extensao de arquivo ou hives de sistema (SAM/SECURITY/SYSTEM bruto) -
    essas categorias sao as que mais quebram instalacoes em limpadores
    genericos e foram deliberadamente deixadas de fora.
#>

. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\SecurityHelper.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\Logger.ps1"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# ---------------------------------------------------------------------------
# Definicao das categorias seguras de varredura
# ---------------------------------------------------------------------------

function Get-RegistryScanCategories {
    return @(
        @{
            Name = "Entradas de Desinstalacao Orfas"
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
        }
    )
}

# ---------------------------------------------------------------------------
# Varredura (somente leitura, com barra de progresso em tempo real)
# ---------------------------------------------------------------------------

function Get-RegistryJunkReport {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  VARREDURA DO REGISTRO" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $categories = Get-RegistryScanCategories
    $findings = New-Object System.Collections.Generic.List[Object]
    $totalCategories = $categories.Count
    $catIndex = 0

    foreach ($cat in $categories) {
        $catIndex++
        $baseActivity = "Varrendo registro"
        Write-Progress -Activity $baseActivity -Status "$($cat.Name)..." -PercentComplete ([int](($catIndex - 1) / $totalCategories * 100))

        foreach ($hivePath in $cat.Hives) {
            if (-not (Test-Path $hivePath -ErrorAction SilentlyContinue)) { continue }

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
                            Write-Progress -Activity $baseActivity -Status "$($cat.Name): $($v.Name)" `
                                -PercentComplete ([int](($catIndex - 1) / $totalCategories * 100 + ($i / $total) * (100 / $totalCategories)))
                        }
                        $checkTarget = if ($cat.ValueNameIsPath) { $v.Name } else { $v.Value }
                        if ([string]::IsNullOrWhiteSpace($checkTarget)) { continue }
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
                            Write-Progress -Activity $baseActivity -Status "$($cat.Name): $($key.PSChildName)" `
                                -PercentComplete ([int](($catIndex - 1) / $totalCategories * 100 + ($i / $total) * (100 / $totalCategories)))
                        }
                        try {
                            if (& $cat.Check $key) {
                                $findings.Add([PSCustomObject]@{
                                    Category  = $cat.Name
                                    KeyPath   = $key.PSPath -replace '^Microsoft\.PowerShell\.Core\\Registry::', ''
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
    Write-Log "Varredura de registro concluida: $($findings.Count) itens orfaos encontrados." "INFO"
    return $findings
}

function Show-RegistryJunkReport {
    param($Findings)

    if ($Findings.Count -eq 0) {
        Write-Host "`n      [OK] Nenhuma chave orfa encontrada nas categorias seguras verificadas." -ForegroundColor Green
        return
    }

    Write-Host "`n      $($Findings.Count) item(ns) orfao(s) encontrado(s):" -ForegroundColor Yellow
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
# Limpeza (com backup obrigatorio + barra de progresso)
# ---------------------------------------------------------------------------

function Clear-RegistryJunk {
    param($Findings)

    if ($Findings.Count -eq 0) { return }

    Write-Host "`n[>] Fazendo backup das chaves afetadas antes de excluir..." -ForegroundColor Yellow
    $backupOk = Backup-RegistryFindings -Findings $Findings
    if (-not $backupOk) {
        Write-Host "      [ERRO] Backup falhou. Abortando limpeza por seguranca." -ForegroundColor Red
        Write-Log "Limpeza de registro abortada: backup falhou." "ERROR"
        return
    }

    $total = $Findings.Count
    $i = 0
    $removed = 0
    $failed = 0

    foreach ($item in $Findings) {
        $i++
        Write-Progress -Activity "Limpando registro" -Status "$($item.Category): $($item.Detail)" -PercentComplete ([int]($i / $total * 100))
        try {
            if ($item.ValueName) {
                Remove-ItemProperty -Path $item.KeyPath -Name $item.ValueName -Force -ErrorAction Stop
            } else {
                Remove-Item -Path $item.KeyPath -Recurse -Force -ErrorAction Stop
            }
            $removed++
        } catch {
            $failed++
        }
    }
    Write-Progress -Activity "Limpando registro" -Completed

    Write-Host "`n      [OK] $removed chave(s)/valor(es) removido(s). $failed falha(s)." -ForegroundColor Green
    Write-Log "Limpeza de registro: $removed removidos, $failed falhas." "SUCCESS"
}

# ---------------------------------------------------------------------------
# Menu
# ---------------------------------------------------------------------------

function Invoke-RegistryScan {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  VARREDURA E LIMPEZA DO REGISTRO" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Categorias verificadas: Uninstall orfas, SharedDLLs quebradas," -ForegroundColor DarkGray
    Write-Host "  App Paths quebrados, MUICache obsoleto. Nada de CLSID/COM/hives" -ForegroundColor DarkGray
    Write-Host "  de sistema - essas ficam de fora por seguranca." -ForegroundColor DarkGray
    Write-Host "`n  1. Apenas Varrer (relatorio, nada e alterado)"
    Write-Host "  2. Varrer e Limpar (com backup automatico + confirmacao)"
    Write-Host "  3. Voltar ao Menu Principal"
    Write-Host "`n========================================" -ForegroundColor Cyan

    $choice = Read-Host "Digite o numero da sua escolha"
    $choice = $choice -replace '\s+', ''

    if (-not (Test-ValidNumericInput -Value $choice -Min 1 -Max 3)) {
        Write-Host "Opcao invalida." -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }

    if ($choice -eq "3") { return }

    $findings = Get-RegistryJunkReport
    Show-RegistryJunkReport -Findings $findings

    if ($choice -eq "2" -and $findings.Count -gt 0) {
        $confirm = Read-Host "`nConfirmar a exclusao dos $($findings.Count) item(ns) acima? Um backup sera feito antes. (S/N)"
        if ($confirm -match '^[Ss]') {
            Clear-RegistryJunk -Findings $findings
        } else {
            Write-Host "      Limpeza cancelada pelo usuario." -ForegroundColor Yellow
            Write-Log "Limpeza de registro cancelada pelo usuario apos revisao do relatorio." "INFO"
        }
    }
}
