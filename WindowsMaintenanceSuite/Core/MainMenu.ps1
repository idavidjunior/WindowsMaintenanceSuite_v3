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

# Importar módulos de Manutenção e Diagnóstico
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Modules\EssentialMaintenance.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Modules\UltimateMaintenance.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Modules\DeepDiagnostics.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Modules\SmartDiagnostics.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Modules\RegistryBackupRestore.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Modules\SystemTweaks.ps1"

function Show-MainMenu {
    while ($true) {
        Clear-Host
        Write-Host "=========================================" -ForegroundColor Green
        Write-Host "  Windows Maintenance Suite - Menu Principal " -ForegroundColor Green
        Write-Host "=========================================" -ForegroundColor Green
        Write-Host "\nSelecione uma opção:"
        Write-Host "  1. Manutenção Essencial"
        Write-Host "  2. Manutenção Completa"
        Write-Host "  3. Diagnósticos Aprofundados"
        Write-Host "  4. Diagnósticos Inteligentes (SMART)"
        Write-Host "  5. Backup do Registro"
        Write-Host "  6. Restaurar Registro (CUIDADO!)"
        Write-Host "  7. Ajustes de Sistema (Tweaks)"
        Write-Host "  8. Sair"
        Write-Host "\n=========================================" -ForegroundColor Green

        $choice = Read-Host "Digite o número da sua escolha"

        switch ($choice) {
            "1" {
                Write-Log "Iniciando Manutenção Essencial."
                Invoke-EssentialMaintenance
                Pause-Script
            }
            "2" {
                Write-Log "Iniciando Manutenção Completa."
                Invoke-UltimateMaintenance
                Pause-Script
            }
            "3" {
                Write-Log "Iniciando Diagnósticos Aprofundados."
                Invoke-DeepDiagnostics
                Pause-Script
            }
            "4" {
                Write-Log "Iniciando Diagnósticos Inteligentes (SMART)."
                Invoke-SmartDiagnostics
                Pause-Script
            }
            "5" {
                Write-Log "Iniciando Backup do Registro."
                Backup-Registry
                Pause-Script
            }
            "6" {
                Write-Log "Iniciando Restauração do Registro."
                $backupFiles = Get-ChildItem -Path "C:\WMS_RegistryBackups" -Filter "RegistryBackup_*.reg" | Select-Object -ExpandProperty FullName
                if ($backupFiles.Count -gt 0) {
                    Write-Host "\nBackups de Registro disponíveis:" -ForegroundColor Yellow
                    for ($i = 0; $i -lt $backupFiles.Count; $i++) {
                        Write-Host "  $($i+1). $($backupFiles[$i])"
                    }
                    $backupChoice = Read-Host "Selecione o número do backup para restaurar"
                    if ($backupChoice -match "^\d+$" -and $backupChoice -ge 1 -and $backupChoice -le $backupFiles.Count) {
                        Restore-Registry -BackupFile $backupFiles[$backupChoice-1]
                    } else {
                        Write-Host "Escolha inválida." -ForegroundColor Red
                    }
                } else {
                    Write-Host "Nenhum backup de registro encontrado em C:\WMS_RegistryBackups." -ForegroundColor Yellow
                }
                Pause-Script
            }
            "7" {
                Write-Log "Iniciando Ajustes de Sistema (Tweaks)."
                Invoke-SystemTweaks
                Pause-Script
            }
            "8" {
                Write-Log "Saindo do Windows Maintenance Suite."
                return
            }
            default {
                Write-Host "Opção inválida. Por favor, tente novamente." -ForegroundColor Red
                Start-Sleep -Seconds 2
            }
        }
    }
}

function Pause-Script {
    Write-Host "\nPressione qualquer tecla para continuar..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# Iniciar o menu principal
Show-MainMenu
