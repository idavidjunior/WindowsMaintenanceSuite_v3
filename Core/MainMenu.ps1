<#
.SYNOPSIS
    Menu principal interativo para o Windows Maintenance Suite.
.DESCRIPTION
    Este script PowerShell fornece um menu interativo para o usuario escolher
    diferentes modulos de manutencao e diagnostico do sistema.
#>

# Garantir encoding UTF-8 (corrige acentos no console)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Desbloquear todos os .ps1 do projeto (remove o Mark-of-the-Web de arquivos
# baixados via ZIP, que bloqueiam execucao mesmo sob -ExecutionPolicy Bypass
# em alguns cenarios). Silencioso e nao-fatal: se falhar, o launcher segue.
try {
    $projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Definition)
    Get-ChildItem -Path $projectRoot -Recurse -Filter "*.ps1" -ErrorAction SilentlyContinue |
        Unblock-File -ErrorAction SilentlyContinue
} catch {
    # Nao interrompe o launcher se o unblock falhar (ex: sem permissao no volume)
}

# Importar modulos Core
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\Logger.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\ConfigManager.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\HealthEngine.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\SecurityHelper.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\Scheduler.ps1"

# Validar privilegios de administrador (verificacao UNICA, em nivel de menu)
Require-Administrator

# Importar modulos de Manutencao e Diagnostico
$modRoot = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) '..\Modules'
. (Join-Path $modRoot 'EssentialMaintenance.ps1')
. (Join-Path $modRoot 'UltimateMaintenance.ps1')
. (Join-Path $modRoot 'DeepDiagnostics.ps1')
. (Join-Path $modRoot 'SmartDiagnostics.ps1')
. (Join-Path $modRoot 'RegistryBackupRestore.ps1')
. (Join-Path $modRoot 'SystemTweaks.ps1')
. (Join-Path $modRoot 'PerformanceMonitor.ps1')
. (Join-Path $modRoot 'DeepCleaning.ps1')
. (Join-Path $modRoot 'SystemLightweight.ps1')
. (Join-Path $modRoot 'DriverManager.ps1')
. (Join-Path $modRoot 'SecurityScan.ps1')
. (Join-Path $modRoot 'RegistryScanner.ps1')
. (Join-Path $modRoot 'QuickTools.ps1')

# Verificação rápida de carregamento
if (-not (Get-Command Invoke-RegistryScan -ErrorAction SilentlyContinue)) {
    Write-Error "Falha ao carregar o módulo RegistryScanner (Invoke-RegistryScan não encontrado)."
    pause
    exit 1
}

function Show-MainMenu {
    while ($true) {
        Clear-Host
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "  WINDOWS MAINTENANCE SUITE" -ForegroundColor Green
        Write-Host "  MENU PRINCIPAL" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "`nSelecione uma opcao:"
        Write-Host "  --- MANUTENCAO ---"
        Write-Host "  1. Manutencao Essencial"
        Write-Host "  2. Manutencao Completa"
        Write-Host "  --- LIMPEZA & LEVEZA ---"
        Write-Host "  3. Limpeza Profunda (libera espaco)"
        Write-Host "  4. Sistema Leve (boot/RAM/servicos)"
        Write-Host "  --- DIAGNOSTICOS ---"
        Write-Host "  5. Diagnostico Aprofundado"
        Write-Host "  6. Diagnostico Inteligente (SMART)"
        Write-Host "  7. Monitor de Desempenho"
        Write-Host "  8. Gerenciador de Drivers"
        Write-Host "  --- OTIMIZACAO & SEGURANCA ---"
        Write-Host "  9. Ajustes de Sistema (Tweaks)"
        Write-Host " 10. Backup do Registro"
        Write-Host " 11. Restaurar Registro (CUIDADO!)"
        Write-Host " 12. Manutencao Agendada"
        Write-Host " 13. Verificacao de Virus (Windows Defender)"
        Write-Host " 14. Varredura e Limpeza do Registro"
        Write-Host " 15. Ferramentas Nativas do Windows (defrag, servicos, MRT, etc.)"
        Write-Host " 16. Sair"
        Write-Host "`n========================================" -ForegroundColor Green

        $choice = Read-Host "Digite o numero da sua escolha"

        # Remover espacos em branco
        $choice = $choice -replace '\s+', ''

        # Validar input
        $isValid = Test-ValidNumericInput -Value $choice -Min 1 -Max 16

        if (-not $isValid) {
            Write-Host "Opcao invalida. Por favor, digite um numero entre 1 e 16." -ForegroundColor Red
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
                Write-Log "Iniciando Limpeza Profunda."
                Invoke-DeepCleaning
                Wait-KeyPress
            }
            "4" {
                Write-Log "Iniciando Sistema Leve."
                Invoke-SystemLightweight
                Wait-KeyPress
            }
            "5" {
                Write-Log "Iniciando Diagnosticos Aprofundados."
                Invoke-DeepDiagnostics
                Wait-KeyPress
            }
            "6" {
                Write-Log "Iniciando Diagnosticos Inteligentes (SMART)."
                Invoke-SmartDiagnostics
                Wait-KeyPress
            }
            "7" {
                Write-Log "Iniciando Monitor de Desempenho."
                Invoke-PerformanceMonitor
            }
            "8" {
                Write-Log "Iniciando Gerenciador de Drivers."
                Invoke-DriverManager
                Wait-KeyPress
            }
            "9" {
                Write-Log "Iniciando Ajustes de Sistema (Tweaks)."
                Invoke-SystemTweaks
                Wait-KeyPress
            }
            "10" {
                Write-Log "Iniciando Backup do Registro."
                Backup-Registry
                Wait-KeyPress
            }
            "11" {
                Write-Log "Iniciando Restauracao do Registro."
                $backupPath = Get-SafeBackupPath
                $backupFiles = @()
                if (Test-Path -Path $backupPath) {
                    $backupFiles = Get-ChildItem -Path $backupPath -Filter "RegistryBackup_*.reg" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
                }

                if ($backupFiles -and $backupFiles.Count -gt 0) {
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
            "12" {
                Write-Log "Abrindo Manutencao Agendada."
                Invoke-MaintenanceScheduler
                Wait-KeyPress
            }
            "13" {
                Write-Log "Iniciando Verificacao de Virus (Windows Defender)."
                Invoke-SecurityScan
                Wait-KeyPress
            }
            "14" {
                Write-Log "Iniciando Varredura e Limpeza do Registro."
                Invoke-RegistryScan
                Wait-KeyPress
            }
            "15" {
                Write-Log "Abrindo Ferramentas Nativas do Windows."
                Invoke-QuickToolsMenu
                Wait-KeyPress
            }
            "16" {
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
