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

$corePath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$modRoot = Join-Path $corePath '..\Modules'

$coreModules = @('Logger.ps1','ConfigManager.ps1','HealthEngine.ps1','SecurityHelper.ps1','Scheduler.ps1')
foreach ($mod in $coreModules) {
    Import-Module (Join-Path $corePath $mod) -Force -DisableNameChecking
}

# Validar privilegios de administrador (verificacao UNICA, em nivel de menu)
Require-Administrator

$moduleFiles = @(
    'EssentialMaintenance.ps1','UltimateMaintenance.ps1','DeepDiagnostics.ps1','SmartDiagnostics.ps1',
    'RegistryBackupRestore.ps1','SystemTweaks.ps1','PerformanceMonitor.ps1','DeepCleaning.ps1',
    'SystemLightweight.ps1','DriverManager.ps1','SecurityScan.ps1','RegistryScanner.ps1',
    'QuickTools.ps1','SelfUpdate.ps1','PackageManager.ps1','Profiles.ps1','Hardening.ps1',
    'DiskSpaceAnalyzer.ps1','MemoryManager.ps1','Winapp2Parser.ps1'
)
foreach ($mod in $moduleFiles) {
    Import-Module (Join-Path $modRoot $mod) -Force -DisableNameChecking
}

# Verificacao rapida de carregamento
if (-not (Get-Command Invoke-RegistryScan -ErrorAction SilentlyContinue)) {
    Write-Error "Falha ao carregar o modulo RegistryScanner (Invoke-RegistryScan nao encontrado)."
    pause
    exit 1
}
if (-not (Get-Command Update-WMS -ErrorAction SilentlyContinue)) {
    Write-Error "Falha ao carregar o modulo SelfUpdate (Update-WMS nao encontrado)."
    pause
    exit 1
}
if (-not (Get-Command Install-App -ErrorAction SilentlyContinue)) {
    Write-Error "Falha ao carregar o modulo PackageManager (Install-App nao encontrado)."
    pause
    exit 1
}
if (-not (Get-Command Set-WMSProfile -ErrorAction SilentlyContinue)) {
    Write-Error "Falha ao carregar o modulo Profiles (Set-WMSProfile nao encontrado)."
    pause
    exit 1
}
if (-not (Get-Command Invoke-Hardening -ErrorAction SilentlyContinue)) {
    Write-Error "Falha ao carregar o modulo Hardening (Invoke-Hardening nao encontrado)."
    pause
    exit 1
}
if (-not (Get-Command Invoke-MemoryManager -ErrorAction SilentlyContinue)) {
    Write-Error "Falha ao carregar o modulo MemoryManager (Invoke-MemoryManager nao encontrado)."
    pause
    exit 1
}
if (-not (Get-Command Invoke-Winapp2Scan -ErrorAction SilentlyContinue)) {
    Write-Error "Falha ao carregar o modulo Winapp2Parser (Invoke-Winapp2Scan nao encontrado)."
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
        Write-Host "`nSelecione uma Opção:"
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
        Write-Host " 16. Analisador de Espaco em Disco"
        Write-Host " 17. Atualizacao Automatica (Self-Update)"
        Write-Host " 18. Gerenciador de Pacotes (WinGet/Choco/Scoop)"
        Write-Host " 19. Perfis de Otimizacao (Gamer/Dev/Server/Battery)"
        Write-Host " 20. Hardening de Seguranca (Baseline/Strict)"
        Write-Host " 21. Gerenciador de Memoria RAM"
        Write-Host " 22. Regras da Comunidade - Winapp2 (somente relatorio)"
        Write-Host " 23. Sair"
        Write-Host "`n========================================" -ForegroundColor Green

        $choice = Read-Host "Digite o numero da sua escolha"

        # Remover espacos em branco
        $choice = $choice -replace '\s+', ''

        # Validar input
        $isValid = Test-ValidNumericInput -Value $choice -Min 1 -Max 23

        if (-not $isValid) {
            Write-Host "Opção inválida. Por favor, digite um numero entre 1 e 23." -ForegroundColor Red
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
                Write-Log "Iniciando restauração do Registro."
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
                    if ($backupChoice -match "^\d+$" -and [int]$backupChoice -ge 1 -and [int]$backupChoice -le $backupFiles.Count) {
                        Restore-Registry -BackupFile $backupFiles[$backupChoice-1]
                    } else {
                        Write-Host "Escolha inválida." -ForegroundColor Red
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
                Write-Log "Iniciando Analisador de Espaco em Disco."
                Invoke-DiskSpaceAnalyzer
                Wait-KeyPress
            }
            "17" {
                Write-Log "Iniciando Auto-Atualizacao."
                Update-WMS
                Wait-KeyPress
            }
            "18" {
                Write-Log "Abrindo Gerenciador de Pacotes."
                Invoke-PackageManagerMenu
                Wait-KeyPress
            }
            "19" {
                Write-Log "Aplicando Perfil de Otimizacao."
                Invoke-ProfileMenu
                Wait-KeyPress
            }
            "20" {
                Write-Log "Executando Hardening de Seguranca."
                Invoke-HardeningMenu
                Wait-KeyPress
            }
            "21" {
                Write-Log "Abrindo Gerenciador de Memoria RAM."
                Invoke-MemoryManager
            }
            "22" {
                Write-Log "Abrindo varredura de regras da comunidade (Winapp2)."
                Invoke-Winapp2Scan
                Wait-KeyPress
            }
            "23" {
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

# Iniciar o menu principal
Show-MainMenu
