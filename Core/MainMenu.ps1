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
. (Join-Path $modRoot 'SelfUpdate.ps1')
. (Join-Path $modRoot 'PackageManager.ps1')
. (Join-Path $modRoot 'Profiles.ps1')
. (Join-Path $modRoot 'Hardening.ps1')

# Verificação rápida de carregamento
if (-not (Get-Command Invoke-RegistryScan -ErrorAction SilentlyContinue)) {
    Write-Error "Falha ao carregar o módulo RegistryScanner (Invoke-RegistryScan não encontrado)."
    pause
    exit 1
}
if (-not (Get-Command Update-WMS -ErrorAction SilentlyContinue)) {
    Write-Error "Falha ao carregar o módulo SelfUpdate (Update-WMS não encontrado)."
    pause
    exit 1
}
if (-not (Get-Command Install-App -ErrorAction SilentlyContinue)) {
    Write-Error "Falha ao carregar o módulo PackageManager (Install-App não encontrado)."
    pause
    exit 1
}
if (-not (Get-Command Set-WMSProfile -ErrorAction SilentlyContinue)) {
    Write-Error "Falha ao carregar o módulo Profiles (Set-WMSProfile não encontrado)."
    pause
    exit 1
}
if (-not (Get-Command Invoke-Hardening -ErrorAction SilentlyContinue)) {
    Write-Error "Falha ao carregar o módulo Hardening (Invoke-Hardening não encontrado)."
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
        Write-Host " 16. Atualizacao Automatica (Self-Update)"
        Write-Host " 17. Gerenciador de Pacotes (WinGet/Choco/Scoop)"
        Write-Host " 18. Perfis de Otimizacao (Gamer/Dev/Server/Battery)"
        Write-Host " 19. Hardening de Seguranca (Baseline/Strict)"
        Write-Host " 20. Sair"
        Write-Host "`n========================================" -ForegroundColor Green

        $choice = Read-Host "Digite o numero da sua escolha"

        # Remover espacos em branco
        $choice = $choice -replace '\s+', ''

        # Validar input
        $isValid = Test-ValidNumericInput -Value $choice -Min 1 -Max 20

        if (-not $isValid) {
            Write-Host "Opcao invalida. Por favor, digite um numero entre 1 e 20." -ForegroundColor Red
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
                Write-Log "Iniciando Auto-Atualizacao."
                Update-WMS
                Wait-KeyPress
            }
            "17" {
                Write-Log "Abrindo Gerenciador de Pacotes."
                Invoke-PackageManagerMenu
                Wait-KeyPress
            }
            "18" {
                Write-Log "Aplicando Perfil de Otimizacao."
                Invoke-ProfileMenu
                Wait-KeyPress
            }
            "19" {
                Write-Log "Executando Hardening de Seguranca."
                Invoke-HardeningMenu
                Wait-KeyPress
            }
            "20" {
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

function Invoke-PackageManagerMenu {
    while ($true) {
        Clear-Host
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  GERENCIADOR DE PACOTES" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "`n  1. Instalar aplicativo (informar ID)"
        Write-Host "  2. Atualizar todos os pacotes"
        Write-Host "  3. Remover bloatware padrão"
        Write-Host "  4. Voltar"
        Write-Host "`n========================================" -ForegroundColor Cyan
        $c = Read-Host "Escolha"
        $c = $c -replace '\s+',''
        switch ($c) {
            "1" { $id = Read-Host "ID do pacote (ex: Microsoft.VSCode)"; Install-App -Id $id; Wait-KeyPress }
            "2" { Update-AllApps; Wait-KeyPress }
            "3" { Uninstall-Bloat; Wait-KeyPress }
            "4" { return }
            default { Write-Host "Opção inválida." -ForegroundColor Red; Start-Sleep 1 }
        }
    }
}

function Invoke-ProfileMenu {
    while ($true) {
        Clear-Host
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  PERFIS DE OTIMIZAÇÃO" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "`n  1. Gamer"
        Write-Host "  2. Developer"
        Write-Host "  3. Server"
        Write-Host "  4. BatterySaver"
        Write-Host "  5. Default (Balanceado)"
        Write-Host "  6. Voltar"
        Write-Host "`n========================================" -ForegroundColor Cyan
        $c = Read-Host "Escolha"
        $c = $c -replace '\s+',''
        switch ($c) {
            "1" { Set-WMSProfile -Profile Gamer; Wait-KeyPress }
            "2" { Set-WMSProfile -Profile Developer; Wait-KeyPress }
            "3" { Set-WMSProfile -Profile Server; Wait-KeyPress }
            "4" { Set-WMSProfile -Profile BatterySaver; Wait-KeyPress }
            "5" { Set-WMSProfile -Profile Default; Wait-KeyPress }
            "6" { return }
            default { Write-Host "Opção inválida." -ForegroundColor Red; Start-Sleep 1 }
        }
    }
}

function Invoke-HardeningMenu {
    while ($true) {
        Clear-Host
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  HARDENING DE SEGURANÇA" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "`n  1. Baseline"
        Write-Host "  2. Strict"
        Write-Host "  3. Voltar"
        Write-Host "`n========================================" -ForegroundColor Cyan
        $c = Read-Host "Escolha"
        $c = $c -replace '\s+',''
        switch ($c) {
            "1" { Invoke-Hardening -Level Baseline; Wait-KeyPress }
            "2" { Invoke-Hardening -Level Strict; Wait-KeyPress }
            "3" { return }
            default { Write-Host "Opção inválida." -ForegroundColor Red; Start-Sleep 1 }
        }
    }
}

function Wait-KeyPress {
    Write-Host "`nPressione qualquer tecla para continuar..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# Iniciar o menu principal
Show-MainMenu
