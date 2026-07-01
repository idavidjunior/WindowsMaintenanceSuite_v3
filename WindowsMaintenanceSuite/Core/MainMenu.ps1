<#
.SYNOPSIS
    Menu principal interativo para o Windows Maintenance Suite.
.DESCRIPTION
    Este script PowerShell fornece um menu interativo para o usuário escolher
    diferentes módulos de manutenção e diagnóstico do sistema.
#>

# Importar módulos Core
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\Logger.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\ConfigManager.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\HealthEngine.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\SecurityHelper.ps1"

# Validar privilégios de administrador
Require-Administrator

# Importar módulos de Manutenção e Diagnóstico
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Modules\EssentialMaintenance.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Modules\UltimateMaintenance.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Modules\DeepDiagnostics.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Modules\SmartDiagnostics.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Modules\RegistryBackupRestore.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Modules\SystemTweaks.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Modules\PerformanceMonitor.ps1"

function Show-MainMenu {
    while ($true) {
        Clear-Host
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "  WINDOWS MAINTENANCE SUITE" -ForegroundColor Green
        Write-Host "  MENU PRINCIPAL" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "`nSelecione uma opcao:"
        Write-Host "  1. Manutencao Essencial"
        Write-Host "  2. Manutencao Completa"
        Write-Host "  3. Diagnosticos Aprofundados"
        Write-Host "  4. Diagnosticos Inteligentes (SMART)"
        Write-Host "  5. Backup do Registro"
        Write-Host "  6. Restaurar Registro (CUIDADO!)"
        Write-Host "  7. Ajustes de Sistema (Tweaks)"
        Write-Host "  8. Monitor de Desempenho"
        Write-Host "  9. Sair"
        Write-Host "`n========================================" -ForegroundColor Green

        $choice = Read-Host "Digite o numero da sua escolha"

        # Remover espaços em branco
        $choice = $choice -replace '\s+', ''

        # Validar input
        if (-not (Test-ValidNumericInput -Input $choice -Min 1 -Max 9)) {
            Write-Host "Opcao invalida. Por favor, digite um numero entre 1 e 9." -ForegroundColor Red
            Start-Sleep -Seconds 2
            continue
        }

        switch ($choice) {
            "1" {
                Write-Log "Iniciando Manutencao Essencial."
                Invoke-EssentialMaintenance
                Wait-KeyPress
            }
            "2" {
                Write-Log "Iniciando Manutencao Completa."
                Invoke-UltimateMaintenance
                Wait-KeyPress
            }
            "3" {
                Write-Log "Iniciando Diagnosticos Aprofundados."
                Invoke-DeepDiagnostics
                Wait-KeyPress
            }
            "4" {
                Write-Log "Iniciando Diagnosticos Inteligentes (SMART)."
                Invoke-SmartDiagnostics
                Wait-KeyPress
            }
            "5" {
                Write-Log "Iniciando Backup do Registro."
                Backup-Registry
                Wait-KeyPress
            }
            "6" {
                Write-Log "Iniciando Restauracao do Registro."
                $backupFiles = Get-ChildItem -Path "C:\WMS_RegistryBackups" -Filter "RegistryBackup_*.reg" | Select-Object -ExpandProperty FullName
                if ($backupFiles.Count -gt 0) {
                    Write-Host "`nBackups de Registro disponiveis:" -ForegroundColor Yellow
                    for ($i = 0; $i -lt $backupFiles.Count; $i++) {
                        $backupSize = [Math]::Round((Get-Item $backupFiles[$i]).Length / 1MB, 2)
                        Write-Host "  $($i+1). $($backupFiles[$i]) ($backupSize MB)"
                    }
                    $backupChoice = Read-Host "Selecione o numero do backup para restaurar"
                    if ($backupChoice -match "^\d+$" -and $backupChoice -ge 1 -and $backupChoice -le $backupFiles.Count) {
                        Restore-Registry -BackupFile $backupFiles[$backupChoice-1]
                    } else {
                        Write-Host "Escolha invalida." -ForegroundColor Red
                    }
                } else {
                    Write-Host "Nenhum backup de registro encontrado em C:\WMS_RegistryBackups." -ForegroundColor Yellow
                }
                Wait-KeyPress
            }
            "7" {
                Write-Log "Iniciando Ajustes de Sistema (Tweaks)."
                Invoke-SystemTweaks
                Wait-KeyPress
            }
            "8" {
                Write-Log "Iniciando Monitor de Desempenho."
                Invoke-PerformanceMonitor
            }
            "9" {
                Write-Log "Saindo do Windows Maintenance Suite."
                return
            }
            default {
                Write-Host "Opcao invalida. Por favor, tente novamente." -ForegroundColor Red
                Start-Sleep -Seconds 2
            }
        }
    }
}

function Wait-KeyPress {
    Write-Host "`nPressione qualquer tecla para continuar..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# Iniciar o menu principal
Show-MainMenu
