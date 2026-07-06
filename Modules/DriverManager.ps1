<#
.SYNOPSIS
    Modulo Gerenciador de Drivers (Driver Manager).
.DESCRIPTION
    Lista, atualiza (via Windows Update nativo), faz backup e remove drivers
    superseded/orfÃ£os. Usa APENAS ferramentas nativas do Windows
    (pnputil, dism, COM do Windows Update) - sem baixar nada de terceiros.
#>

# Importar Core
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\SecurityHelper.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\Logger.ps1"

# Garantir encoding UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# ---------------------------------------------------------------------------
# Funcoes internas
# ---------------------------------------------------------------------------

function Get-InstalledDrivers {
    <#
    .SYNOPSIS
        Lista drivers de terceiros publicados (Third-Party) via pnputil.
    #>
    try {
        $output = pnputil /enum-drivers 2>&1
        $drivers = @()
        $current = @{}

        foreach ($line in $output) {
            $line = "$line"
            if ($line -match '^\s*Nome (da Publicacao|do Publicador|Published Name)\s*:\s*(.+)$' -or
                $line -match '^\s*Published Name\s*:\s*(.+)$' -or
                $line -match '^\s*(?:Original Name|Nome Original)\s*:\s*(.+)$' -or
                $line -match '^\s*Nome do Arquivo Original\s*:\s*(.+)$') {
                if ($current.PublishedName) { $drivers += [PSCustomObject]$current; $current = @{} }
                $current.PublishedName = $matches[1].Trim()
            }
            elseif ($line -match '^\s*Nome da Classe\s*:\s*(.+)$' -or $line -match '^\s*Class Name\s*:\s*(.+)$') {
                $current.Class = $matches[1].Trim()
            }
            elseif ($line -match '^\s*(?:Fornecedor|Provider)\s*:\s*(.+)$' -or $line -match '^\s*Fabricante do Driver\s*:\s*(.+)$') {
                $current.Provider = $matches[1].Trim()
            }
            elseif ($line -match '^\s*(?:Data|Date)\s*:\s*(.+)$' -or $line -match '^\s*Data do Driver\s*:\s*(.+)$') {
                $current.Date = $matches[1].Trim()
            }
            elseif ($line -match '^\s*(?:Versao|Version)\s*:\s*(.+)$' -or $line -match '^\s*Versao do Driver\s*:\s*(.+)$') {
                $current.Version = $matches[1].Trim()
            }
            elseif ($line -match '^\s*(?:INF|Arquivo INF|Inf)\s*:\s*(.+)$' -or $line -match '^\s*Nome do Arquivo INF\s*:\s*(.+)$') {
                $current.InfFile = $matches[1].Trim()
            }
        }
        if ($current.PublishedName) { $drivers += [PSCustomObject]$current }

        return $drivers
    } catch {
        Write-Host "      [ERRO] Falha ao listar drivers: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
        return @()
    }
}

function Find-DriverUpdatesViaWU {
    <#
    .SYNOPSIS
        Procura atualizacoes de driver disponiveis via Windows Update (COM), nativo.
    .OUTPUTS
        Lista de atualizacoes de driver encontradas.
    #>
    try {
        Write-Host "      [INFO] Conectando ao Windows Update (pode levar alguns minutos)..." -ForegroundColor Cyan
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $searcher.Online = $true
        $result = $searcher.Search("IsInstalled=0 and Type='Driver'")

        $updates = @()
        foreach ($update in $result.Updates) {
            $updates += [PSCustomObject]@{
                Title    = $update.Title
                Driver   = ($update.DriverClass -join ', ')
                Severity = $update.MsrcSeverity
                Size     = if ($update.MaxDownloadSize) { [Math]::Round($update.MaxDownloadSize / 1MB, 2) } else { 0 }
            }
        }
        return $updates
    } catch {
        Write-Host "      [ERRO] Falha ao procurar atualizacoes: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
        return @()
    }
}

function Install-DriverUpdatesViaWU {
    <#
    .SYNOPSIS
        Baixa e instala as atualizacoes de driver disponiveis via Windows Update.
    #>
    try {
        Write-Host "      [INFO] Conectando ao Windows Update..." -ForegroundColor Cyan
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $searcher.Online = $true
        Write-Host "      [INFO] Procurando atualizacoes de driver..." -ForegroundColor Cyan
        $result = $searcher.Search("IsInstalled=0 and Type='Driver'")

        if ($result.Updates.Count -eq 0) {
            Write-Host "      [OK] Nenhuma atualizacao de driver disponivel. Drivers estao atualizados." -ForegroundColor Green
            Write-Log "Busca de drivers: nenhum update disponivel." "SUCCESS"
            return
        }

        Write-Host "`n      Foram encontradas $($result.Updates.Count) atualizacoes de driver:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $result.Updates.Count; $i++) {
            Write-Host "        $($i+1). $($result.Updates.Item($i).Title)"
        }

        $confirm = Read-Host "`n      Baixar e instalar TODAS as atualizacoes de driver agora? (S/N)"
        if ($confirm -ne 'S' -and $confirm -ne 's') {
            Write-Host "      [INFO] Instalacao cancelada pelo usuario." -ForegroundColor Cyan
            return
        }

        # Agrupar em uma colecao para download+instalacao
        $updatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($update in $result.Updates) {
            if ($update.EulaAccepted -eq $false) { $update.AcceptEula() }
            $updatesToInstall.Add($update) | Out-Null
        }

        Write-Host "      [INFO] Baixando atualizacoes..." -ForegroundColor Cyan
        $downloader = $session.CreateUpdateDownloader()
        $downloader.Updates = $updatesToInstall
        $downloadResult = $downloader.Download()

        Write-Host "      [INFO] Instalando atualizacoes..." -ForegroundColor Cyan
        $installer = $session.CreateUpdateInstaller()
        $installer.Updates = $updatesToInstall
        $installResult = $installer.Install()

        if ($installResult.ResultCode -eq 2) {
            Write-Host "      [OK] Drivers atualizados com sucesso! Reinicie o computador para concluir." -ForegroundColor Green
            Write-Log "Atualizacao de drivers via Windows Update concluida com sucesso." "SUCCESS"
        } elseif ($installResult.ResultCode -eq 3) {
            Write-Host "      [AVISO] Atualizacao concluida com sucesso parcial. Reinicie o computador." -ForegroundColor Yellow
            Write-Log "Atualizacao de drivers: sucesso parcial." "WARNING"
        } else {
            Write-Host "      [ERRO] Falha ao instalar atualizacoes (codigo: $($installResult.ResultCode))." -ForegroundColor Red
            Write-Log "Falha ao instalar atualizacoes de driver (codigo $($installResult.ResultCode))." "ERROR"
        }
    } catch {
        Write-Host "      [ERRO] Falha ao instalar atualizacoes de driver: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
        Write-Log "Erro ao instalar atualizacoes de driver: $_" "ERROR"
    }
}

function Get-SupersededDrivers {
    <#
    .SYNOPSIS
        Identifica drivers superseded (versoes antigas de um mesmo provider/classe).
    #>
    try {
        $all = Get-InstalledDrivers
        if (-not $all -or $all.Count -eq 0) { return @() }

        # Agrupar por Provider+Class e ordenar por data/version para encontrar antigos
        $groups = $all | Group-Object -Property { "$($_.Provider)|$($_.Class)" }
        $superseded = @()
        foreach ($grp in $groups) {
            if ($grp.Count -gt 1) {
                # Versoes mais antigas do mesmo provider/classe sao candidatas a remocao
                $sorted = $grp.Group | Sort-Object Date
                $superseded += ($sorted | Select-Object -SkipLast 1)
            }
        }
        return $superseded
    } catch {
        return @()
    }
}

# ---------------------------------------------------------------------------
# Funcao principal
# ---------------------------------------------------------------------------

function Invoke-DriverManager {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  GERENCIADOR DE DRIVERS" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "`nSelecione uma Opção:" -ForegroundColor Cyan
    Write-Host "  1. Listar drivers de terceiros instalados"
    Write-Host "  2. Procurar atualizacoes de driver (Windows Update)"
    Write-Host "  3. Baixar e instalar atualizacoes de driver"
    Write-Host "  4. Backup de todos os drivers atuais"
    Write-Host "  5. Remover drivers antigos/superseded (AVANCADO)"
    Write-Host "  6. Exportar inventario de drivers (CSV)"
    Write-Host "  7. Voltar ao Menu Principal"
    Write-Host "`n========================================" -ForegroundColor Cyan

    $choice = Read-Host "Digite o numero da sua escolha"
    $choice = $choice -replace '\s+', ''

    if (-not (Test-ValidNumericInput -Value $choice -Min 1 -Max 7)) {
        Write-Host "Opção inválida. Digite um numero entre 1 e 7." -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }

    switch ($choice) {
        "1" {
            Write-Host "`n[1] Listando drivers de terceiros..." -ForegroundColor Yellow
            $drivers = Get-InstalledDrivers
            if ($drivers.Count -eq 0) {
                Write-Host "      [INFO] Nenhum driver de terceiro encontrado." -ForegroundColor Cyan
            } else {
                Write-Host "      Encontrados $($drivers.Count) driver(s) de terceiros:`n" -ForegroundColor Green
                $drivers | Format-Table PublishedName, Class, Provider, Version, Date -AutoSize | Out-String | Write-Host
            }
            Write-Log "Listagem de drivers: $($drivers.Count) encontrados." "INFO"
        }
        "2" {
            Write-Host "`n[2] Procurando atualizacoes de driver..." -ForegroundColor Yellow
            $updates = Find-DriverUpdatesViaWU
            if ($updates.Count -eq 0) {
                Write-Host "      [OK] Nenhuma atualizacao de driver disponivel." -ForegroundColor Green
            } else {
                Write-Host "      $($updates.Count) atualizacoes disponiveis:`n" -ForegroundColor Green
                $updates | Format-Table Title, Severity, @{N='Size(MB)';E={$_.Size}} -AutoSize | Out-String | Write-Host
            }
            Write-Log "Busca de drivers: $($updates.Count) atualizacoes encontradas." "INFO"
        }
        "3" {
            Write-Host "`n[3] Baixar e instalar atualizacoes de driver..." -ForegroundColor Yellow
            Install-DriverUpdatesViaWU
        }
        "4" {
            Write-Host "`n[4] Backup de todos os drivers atuais..." -ForegroundColor Yellow
            $backupDir = "C:\WMS_DriverBackups\Drivers_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            try {
                if (-not (Test-Path $backupDir)) {
                    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
                }
                Write-Host "      [INFO] Exportando drivers para: $backupDir" -ForegroundColor Cyan
                Write-Host "      [INFO] Isso pode levar alguns minutos..." -ForegroundColor Cyan
                $dismProc = Start-Process -FilePath "dism.exe" -ArgumentList "/Online /Export-Driver /Destination:`"$backupDir`"" -Wait -PassThru -NoNewWindow
                if ($dismProc.ExitCode -eq 0) {
                    $count = (Get-ChildItem -Path $backupDir -Recurse -Filter "*.inf" -ErrorAction SilentlyContinue).Count
                    Write-Host "      [OK] Backup concluído. $count pacote(s) de driver exportado(s)." -ForegroundColor Green
                    Write-Host "      Local: $backupDir" -ForegroundColor Green
                    Write-Log "Backup de drivers concluído em $backupDir ($count pacotes)." "SUCCESS"
                } else {
                    Write-Host "      [ERRO] DISM falhou ao exportar drivers (codigo $($dismProc.ExitCode))." -ForegroundColor Red
                    Write-Log "Falha no backup de drivers (codigo $($dismProc.ExitCode))." "ERROR"
                }
            } catch {
                Write-Host "      [ERRO] Falha ao fazer backup de drivers: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
                Write-Log "Erro no backup de drivers: $_" "ERROR"
            }
        }
        "5" {
            Write-Host "`n[5] Remover drivers antigos/superseded (AVANCADO)..." -ForegroundColor Yellow
            Write-Host "      [AVISO] Esta operacao remove versoes antigas de drivers." -ForegroundColor Red
            Write-Host "      [AVISO] Faca um backup (Opção 4) antes de continuar." -ForegroundColor Red
            $superseded = Get-SupersededDrivers
            if ($superseded.Count -eq 0) {
                Write-Host "      [OK] Nenhum driver superseded encontrado. Nada a remover." -ForegroundColor Green
            } else {
                Write-Host "      $($superseded.Count) driver(s) candidato(s) a remocao:`n" -ForegroundColor Yellow
                $i = 0
                foreach ($drv in $superseded) {
                    $i++
                    Write-Host ("        {0}. {1} | {2} | v{3} | {4}" -f $i, $drv.PublishedName, $drv.Provider, $drv.Version, $drv.Date)
                }
                $confirm = Read-Host "`n      Remover TODOS os drivers superseded listados? (S/N)"
                if ($confirm -eq 'S' -or $confirm -eq 's') {
                    $removed = 0
                    foreach ($drv in $superseded) {
                        if ($drv.InfFile) {
                            $proc = Start-Process -FilePath "pnputil.exe" -ArgumentList "/delete-driver $($drv.InfFile) /uninstall /force" -Wait -PassThru -NoNewWindow
                            if ($proc.ExitCode -eq 0) { $removed++ }
                        }
                    }
                    Write-Host "      [OK] $removed driver(s) superseded removido(s)." -ForegroundColor Green
                    Write-Log "$removed driver(s) superseded removidos." "SUCCESS"
                } else {
                    Write-Host "      [INFO] Remocao cancelada pelo usuario." -ForegroundColor Cyan
                }
            }
        }
        "6" {
            Write-Host "`n[6] Exportando inventario de drivers..." -ForegroundColor Yellow
            $ReportsDir = Join-Path $PSScriptRoot "..\Reports"
            if (-not (Test-Path $ReportsDir)) {
                New-Item -ItemType Directory -Path $ReportsDir -Force | Out-Null
            }
            $csvPath = Join-Path $ReportsDir "DriversInventory_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
            try {
                $drivers = Get-InstalledDrivers
                if ($drivers.Count -eq 0) {
                    Write-Host "      [INFO] Nenhum driver para exportar." -ForegroundColor Cyan
                } else {
                    $drivers | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
                    Write-Host "      [OK] Inventario exportado: $csvPath ($($drivers.Count) drivers)" -ForegroundColor Green
                    Write-Log "Inventario de drivers exportado: $csvPath" "SUCCESS"
                }
            } catch {
                Write-Host "      [ERRO] Falha ao exportar inventario: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
                Write-Log "Erro ao exportar inventario de drivers: $_" "ERROR"
            }
        }
        "7" { return }
    }
}

Export-ModuleMember -Function *
