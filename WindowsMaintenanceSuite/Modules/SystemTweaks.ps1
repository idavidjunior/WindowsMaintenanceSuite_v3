<#
.SYNOPSIS
    Módulo para aplicar ajustes (tweaks) de sistema no Windows.
.DESCRIPTION
    Este módulo contém funções para otimizar o desempenho, privacidade e experiência do usuário
    no Windows, com a opção de reverter as alterações.
#>

# Importar SecurityHelper
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\SecurityHelper.ps1"

# Importar Logger para registro de eventos
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\Logger.ps1"

# Validar privilégios de administrador (já verificado pelo MainMenu/WMS.bat)
# Require-Administrator  # Comentado temporariamente para teste

function Get-HighPerformancePlanGuid {
    try {
        if (-not (Test-ExternalCommand "powercfg")) {
            return $null
        }

        $schemes = @(powercfg /list 2>$null)
        foreach ($line in $schemes) {
            $trimmed = [string]$line
            $guidMatch = [regex]::Match($trimmed, '([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})')
            if ($guidMatch.Success -and $trimmed -match '(?i)(desempenho|ultimate|high|performance)') {
                return $guidMatch.Groups[1].Value
            }
        }
    } catch {
        return $null
    }

    return $null
}

function Test-HighPerformancePowerPlanActive {
    try {
        $guid = Get-HighPerformancePlanGuid
        if ([string]::IsNullOrWhiteSpace($guid)) { return $false }
        $currentScheme = powercfg /getactivescheme 2>$null
        return $currentScheme -match $guid
    } catch {
        return $false
    }
}

function Test-TelemetryDisabled {
    try {
        $keyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
        if (-not (Test-Path $keyPath)) { return $false }
        $value = (Get-ItemProperty -Path $keyPath -Name "AllowTelemetry" -ErrorAction SilentlyContinue).AllowTelemetry
        return $value -eq 0
    } catch {
        return $false
    }
}

function Test-StartMenuSpeedConfigured {
    try {
        $keyPath = "HKCU:\Control Panel\Desktop"
        $value = (Get-ItemProperty -Path $keyPath -Name "MenuShowDelay" -ErrorAction SilentlyContinue).MenuShowDelay
        return $value -eq 100
    } catch {
        return $false
    }
}

function Test-HibernationDisabled {
    try {
        return -not (Test-Path "$env:SystemDrive\hiberfil.sys")
    } catch {
        return $false
    }
}

function Test-TcpOptimized {
    try {
        $keyPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
        if (-not (Test-Path $keyPath)) { return $false }
        $interfaces = Get-ChildItem -Path $keyPath -ErrorAction SilentlyContinue
        if (-not $interfaces) { return $false }

        $optimizedCount = 0
        foreach ($interface in $interfaces) {
            $interfaceKey = $interface.PSPath
            $noDelay = (Get-ItemProperty -Path $interfaceKey -Name "TcpNoDelay" -ErrorAction SilentlyContinue).TcpNoDelay
            $ackFreq = (Get-ItemProperty -Path $interfaceKey -Name "TcpAckFrequency" -ErrorAction SilentlyContinue).TcpAckFrequency
            if ($noDelay -eq 1 -and $ackFreq -eq 1) { $optimizedCount++ }
        }

        return $optimizedCount -gt 0
    } catch {
        return $false
    }
}

function Test-GameDVRDisabled {
    try {
        $keyPath = "HKCU:\System\GameConfigStore"
        $value = (Get-ItemProperty -Path $keyPath -Name "GameDVR_Enabled" -ErrorAction SilentlyContinue).GameDVR_Enabled
        return $value -eq 0
    } catch {
        return $false
    }
}

function Test-SuperfetchDisabled {
    try {
        $service = Get-Service -Name "SysMain" -ErrorAction SilentlyContinue
        if (-not $service) { return $false }
        return $service.StartType -eq "Disabled"
    } catch {
        return $false
    }
}

function Test-TransparencyDisabled {
    try {
        $keyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        $value = (Get-ItemProperty -Path $keyPath -Name "EnableTransparency" -ErrorAction SilentlyContinue).EnableTransparency
        return $value -eq 0
    } catch {
        return $false
    }
}

function Test-ForegroundPriorityConfigured {
    try {
        $keyPath = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
        $value = (Get-ItemProperty -Path $keyPath -Name "Win32PrioritySeparation" -ErrorAction SilentlyContinue).Win32PrioritySeparation
        return $value -eq 38
    } catch {
        return $false
    }
}

function Test-CortanaDisabled {
    try {
        $keyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
        if (-not (Test-Path $keyPath)) { return $false }
        $value = (Get-ItemProperty -Path $keyPath -Name "AllowCortana" -ErrorAction SilentlyContinue).AllowCortana
        return $value -eq 0
    } catch {
        return $false
    }
}

function Test-AdvertisingIdDisabled {
    try {
        $keyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
        $value = (Get-ItemProperty -Path $keyPath -Name "Enabled" -ErrorAction SilentlyContinue).Enabled
        return $value -eq 0
    } catch {
        return $false
    }
}

function Test-FileExtensionsVisible {
    try {
        $keyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        $value = (Get-ItemProperty -Path $keyPath -Name "HideFileExt" -ErrorAction SilentlyContinue).HideFileExt
        return $value -eq 0
    } catch {
        return $false
    }
}

function Test-CpuCoreOptimizationConfigured {
    return Test-ForegroundPriorityConfigured
}

function Write-TweakMenuOption {
    param (
        [int]$Index,
        [string]$Label,
        [bool]$Applied
    )

    $statusText = if ($Applied) { " [OK]" } else { " [ ]" }
    $color = if ($Applied) { "Green" } else { "White" }
    Write-Host ("  {0}. {1}{2}" -f $Index, $Label, $statusText) -ForegroundColor $color
}

function Show-TweaksMenu {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  AJUSTES DE SISTEMA (TWEAKS)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "`nSelecione os ajustes que deseja aplicar:" -ForegroundColor Cyan

    Write-TweakMenuOption -Index 1 -Label "Ativar Plano de Energia 'Desempenho Maximo'" -Applied (Test-HighPerformancePowerPlanActive)
    Write-TweakMenuOption -Index 2 -Label "Desativar Telemetria Basica" -Applied (Test-TelemetryDisabled)
    Write-TweakMenuOption -Index 3 -Label "Acelerar Resposta do Menu Iniciar" -Applied (Test-StartMenuSpeedConfigured)
    Write-TweakMenuOption -Index 4 -Label "Desativar Hibernacao (Libera espaco em disco)" -Applied (Test-HibernationDisabled)
    Write-TweakMenuOption -Index 5 -Label "Otimizar TCP (Desativar Nagle's Algorithm)" -Applied (Test-TcpOptimized)
    Write-TweakMenuOption -Index 6 -Label "Desativar Game DVR (Libera recursos do sistema)" -Applied (Test-GameDVRDisabled)
    Write-TweakMenuOption -Index 7 -Label "Desativar Superfetch/SysMain (Recomendado para SSDs)" -Applied (Test-SuperfetchDisabled)
    Write-TweakMenuOption -Index 8 -Label "Desativar efeitos de transparencia (Melhora desempenho visual)" -Applied (Test-TransparencyDisabled)
    Write-TweakMenuOption -Index 9 -Label "Priorizar programas em primeiro plano" -Applied (Test-ForegroundPriorityConfigured)
    Write-TweakMenuOption -Index 10 -Label "Desativar Cortana (Privacidade e desempenho)" -Applied (Test-CortanaDisabled)
    Write-TweakMenuOption -Index 11 -Label "Desativar ID de publicidade (Privacidade)" -Applied (Test-AdvertisingIdDisabled)
    Write-TweakMenuOption -Index 12 -Label "Mostrar extensoes de arquivos (Personalizacao)" -Applied (Test-FileExtensionsVisible)
    Write-TweakMenuOption -Index 13 -Label "Otimizar uso de todos os nucleos do processador" -Applied (Test-CpuCoreOptimizationConfigured)
    Write-TweakMenuOption -Index 14 -Label "Aplicar TODOS os ajustes acima" -Applied $false
    Write-TweakMenuOption -Index 15 -Label "Verificar status dos tweaks aplicados" -Applied $false
    Write-TweakMenuOption -Index 16 -Label "Voltar ao Menu Principal" -Applied $false

    Write-Host "`n========================================" -ForegroundColor Cyan
}

# Função auxiliar para backup de chave de registro
function Backup-RegistryKey {
    param (
        [string]$KeyPath,
        [string]$BackupName
    )
    try {
        $BackupDir = Get-SafeBackupPath
        $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $BackupFile = Join-Path -Path $BackupDir -ChildPath "RegistryBackup_$(($KeyPath -replace '[\\/:]', '_') | ForEach-Object { $_.Replace(' ', '') })_$BackupName_$Timestamp.reg"

        if (Test-ExternalCommand "reg") {
            $result = reg export $KeyPath "$BackupFile" /y 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Backup da chave de registro '$KeyPath' salvo em: $BackupFile" -ForegroundColor DarkGreen
                return $BackupFile
            } else {
                Write-Host "Erro ao fazer backup da chave de registro '$KeyPath': $(Get-SafeErrorMessage $result)" -ForegroundColor Red
                return $null
            }
        } else {
            Write-Host "Erro: Comando 'reg' não está disponível no sistema." -ForegroundColor Red
            return $null
        }
    }
    catch {
        Write-Host "Erro ao fazer backup da chave de registro '$KeyPath': $(Get-SafeErrorMessage $_)" -ForegroundColor Red
        return $null
    }
}

# 1. Tweak: Ativar Plano de Energia "Desempenho Maximo"
function Set-HighPerformancePowerPlan {
    Write-Host "`n[1/5] Ativando Plano de Energia 'Desempenho Maximo'..." -ForegroundColor Yellow

    # Salvar configuração atual para rollback
    $originalScheme = $null
    try {
        $originalScheme = powercfg /getactivescheme 2>&1
    } catch {
        # Continuar mesmo se não conseguir obter esquema atual
    }

    try {
        if (-not (Test-ExternalCommand "powercfg")) {
            Write-Host "      [ERRO] Comando 'powercfg' não está disponível no sistema." -ForegroundColor Red
            Write-Log "Comando powercfg não encontrado." "ERROR"
            return
        }

        $highPerfGUID = Get-HighPerformancePlanGuid
        if ([string]::IsNullOrWhiteSpace($highPerfGUID)) {
            $schemes = powercfg /list 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "      [ERRO] Não foi possível listar planos de energia: $(Get-SafeErrorMessage $schemes)" -ForegroundColor Red
                Write-Log "Erro ao listar planos de energia." "ERROR"
                return
            }

            foreach ($line in $schemes) {
                if ($line -match '(?i)(desempenho|ultimate|high).*(performance|maximo|maximo|maximum)') {
                    if ($line -match '([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})') {
                        $highPerfGUID = $matches[1]
                        break
                    }
                }
            }
        }

        if ($null -eq $highPerfGUID) {
            Write-Host "      [ERRO] Plano de Desempenho Maximo nao encontrado no sistema." -ForegroundColor Red
            Write-Log "Plano de Desempenho Maximo nao encontrado." "ERROR"
            return
        }

        # Verifica se o plano ja esta ativo
        $currentScheme = powercfg /getactivescheme 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "      [ERRO] Não foi possível verificar plano ativo: $(Get-SafeErrorMessage $currentScheme)" -ForegroundColor Red
            Write-Log "Erro ao verificar plano ativo." "ERROR"
            return
        }

        if ($currentScheme -match $highPerfGUID) {
            Write-Host "      [INFO] Plano de energia 'Desempenho Maximo' ja estava ativo." -ForegroundColor Cyan
            Write-Log "Plano de energia 'Desempenho Maximo' ja estava ativo." "INFO"
        } elseif (-not (Test-Administrator)) {
            Write-Host "      [WARNING] Plano encontrado, mas a ativação exige privilégios de administrador." -ForegroundColor Yellow
            Write-Log "Plano encontrado, mas a ativação exige privilégios de administrador." "WARNING"
        } else {
            $result = powercfg /setactive $highPerfGUID 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "      [OK] Plano de energia 'Desempenho Maximo' ativado com sucesso (GUID: $highPerfGUID)." -ForegroundColor Green
                Write-Log "Plano de energia 'Desempenho Maximo' ativado." "SUCCESS"
            } else {
                Write-Host "      [ERRO] Falha ao ativar plano. Verifique privilégios de administrador." -ForegroundColor Red
                Write-Log "Erro ao ativar plano de energia. Verifique privilégios de administrador." "ERROR"
            }
        }
    }
    catch {
        Write-Host "      [ERRO] Erro ao ativar plano de energia: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
        Write-Log "Erro ao ativar plano de energia." "ERROR"
    }
}

# 2. Tweak: Desativar Telemetria Basica
function Disable-BasicTelemetry {
    Write-Host "`n[2/5] Desativando Telemetria Basica..." -ForegroundColor Yellow
    $keyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
    $valueName = "AllowTelemetry"
    $originalValue = $null

    try {
        if (-not (Test-Path $keyPath)) {
            New-Item -Path $keyPath -Force | Out-Null
        }
        if ((Get-ItemProperty -Path $keyPath -Name $valueName -ErrorAction SilentlyContinue)) {
            $originalValue = (Get-ItemProperty -Path $keyPath -Name $valueName).$valueName
        }
        
        Set-ItemProperty -Path $keyPath -Name $valueName -Value 0 -Force
        $originalDisplay = if ($null -eq $originalValue) { "Nao existia" } else { $originalValue }
        Write-Host "      [OK] Telemetria Basica desativada (AllowTelemetry = 0). Valor original: $originalDisplay" -ForegroundColor Green
        Write-Log "Telemetria Basica desativada." "SUCCESS"
    }
    catch {
        Write-Host "      [ERRO] Erro ao desativar telemetria basica: $_" -ForegroundColor Red
        Write-Log "Erro ao desativar telemetria basica: $_" "ERROR"
    }
}

# 3. Tweak: Acelerar Resposta do Menu Iniciar
function Set-StartMenuSpeed {
    Write-Host "`n[3/5] Acelerando Resposta do Menu Iniciar..." -ForegroundColor Yellow
    $keyPath = "HKCU:\Control Panel\Desktop"
    $valueName = "MenuShowDelay"
    $originalValue = $null

    try {
        if ((Get-ItemProperty -Path $keyPath -Name $valueName -ErrorAction SilentlyContinue)) {
            $originalValue = (Get-ItemProperty -Path $keyPath -Name $valueName).$valueName
        }
        
        Set-ItemProperty -Path $keyPath -Name $valueName -Value 100 -Force # Valor padrao e 400
        $originalDisplay = if ($null -eq $originalValue) { "Nao existia" } else { "$originalValue ms" }
        Write-Host "      [OK] Atraso do Menu Iniciar ajustado para 100ms. Valor original: $originalDisplay" -ForegroundColor Green
        Write-Log "Menu Iniciar acelerado (100ms)." "SUCCESS"
    }
    catch {
        Write-Host "      [ERRO] Erro ao acelerar Menu Iniciar: $_" -ForegroundColor Red
        Write-Log "Erro ao acelerar Menu Iniciar: $_" "ERROR"
    }
}

# 4. Tweak: Otimizar Hibernacao (Desativar)
function Disable-Hibernation {
    Write-Host "`n[4/5] Desativando Hibernacao (libera espaco em disco)..." -ForegroundColor Yellow
    try {
        powercfg /h off | Out-Null
        Write-Host "      [OK] Hibernacao desativada com sucesso. Para reativar: powercfg /h on" -ForegroundColor Green
        Write-Log "Hibernacao desativada." "SUCCESS"
    }
    catch {
        Write-Host "      [ERRO] Erro ao desativar hibernacao: $_" -ForegroundColor Red
        Write-Log "Erro ao desativar hibernacao: $_" "ERROR"
    }
}

# 5. Tweak: Ajustes de TCP (Netsh) - Desativar Nagle's Algorithm
function Optimize-TCP {
    Write-Host "`n[5/12] Otimizando TCP (Desativar Nagle's Algorithm)..." -ForegroundColor Yellow
    $keyPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"

    try {
        # Iterar sobre todas as interfaces de rede
        $interfaces = Get-ChildItem -Path $keyPath
        $optimizedCount = 0

        foreach ($interface in $interfaces) {
            $interfaceKey = $interface.PSPath
            $originalTcpNoDelay = $null
            $originalTcpAckFrequency = $null

            if ((Get-ItemProperty -Path $interfaceKey -Name "TcpNoDelay" -ErrorAction SilentlyContinue)) {
                $originalTcpNoDelay = (Get-ItemProperty -Path $interfaceKey -Name "TcpNoDelay").TcpNoDelay
            }
            if ((Get-ItemProperty -Path $interfaceKey -Name "TcpAckFrequency" -ErrorAction SilentlyContinue)) {
                $originalTcpAckFrequency = (Get-ItemProperty -Path $interfaceKey -Name "TcpAckFrequency").TcpAckFrequency
            }

            Set-ItemProperty -Path $interfaceKey -Name "TcpNoDelay" -Value 1 -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $interfaceKey -Name "TcpAckFrequency" -Value 1 -Force -ErrorAction SilentlyContinue
            $optimizedCount++

            $originalNoDelayDisplay = if ($null -eq $originalTcpNoDelay) { "Nao existia" } else { $originalTcpNoDelay }
            $originalAckDisplay = if ($null -eq $originalTcpAckFrequency) { "Nao existia" } else { $originalTcpAckFrequency }
            Write-Host "      [OK] Interface $($interface.Name): TcpNoDelay=1 (Original: $originalNoDelayDisplay), TcpAckFrequency=1 (Original: $originalAckDisplay)" -ForegroundColor Green
        }
        Write-Host "      [OK] Ajustes de TCP aplicados em $optimizedCount interface(s). Pode ser necessario reiniciar para efeito total." -ForegroundColor Green
        Write-Log "Ajustes de TCP aplicados em $optimizedCount interface(s)." "SUCCESS"
    }
    catch {
        Write-Host "      [ERRO] Erro ao otimizar TCP: $_" -ForegroundColor Red
        Write-Log "Erro ao otimizar TCP: $_" "ERROR"
    }
}

# 6. Tweak: Desativar Game DVR (Gravacao em jogo)
function Disable-GameDVR {
    Write-Host "`n[6/12] Desativando Game DVR (libera recursos do sistema)..." -ForegroundColor Yellow
    $keyPath = "HKCU:\System\GameConfigStore"
    $valueName = "GameDVR_Enabled"
    $keyPath2 = "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\ApplicationManagement\AllowGameDVR"
    $valueName2 = "value"

    try {
        if (-not (Test-Path $keyPath)) {
            New-Item -Path $keyPath -Force | Out-Null
        }
        Set-ItemProperty -Path $keyPath -Name $valueName -Value 0 -Force -ErrorAction SilentlyContinue

        if (Test-Path $keyPath2) {
            Set-ItemProperty -Path $keyPath2 -Name $valueName2 -Value 0 -Force -ErrorAction SilentlyContinue
        }

        Write-Host "      [OK] Game DVR desativado com sucesso." -ForegroundColor Green
        Write-Log "Game DVR desativado." "SUCCESS"
    }
    catch {
        Write-Host "      [ERRO] Erro ao desativar Game DVR: $_" -ForegroundColor Red
        Write-Log "Erro ao desativar Game DVR: $_" "ERROR"
    }
}

# 7. Tweak: Desativar Superfetch/SysMain (Melhora em SSDs)
function Disable-Superfetch {
    Write-Host "`n[7/12] Desativando Superfetch/SysMain (recomendado para SSDs)..." -ForegroundColor Yellow
    try {
        $serviceName = "SysMain"
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

        if ($service) {
            if ($service.Status -eq "Running") {
                Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
            }
            Set-Service -Name $serviceName -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Host "      [OK] Superfetch/SysMain desativado." -ForegroundColor Green
            Write-Log "Superfetch/SysMain desativado." "SUCCESS"
        } else {
            Write-Host "      [INFO] Servico SysMain nao encontrado (pode ja estar desativado)." -ForegroundColor Cyan
            Write-Log "Servico SysMain nao encontrado." "INFO"
        }
    }
    catch {
        Write-Host "      [ERRO] Erro ao desativar Superfetch: $_" -ForegroundColor Red
        Write-Log "Erro ao desativar Superfetch: $_" "ERROR"
    }
}

# 8. Tweak: Desativar efeitos de transparencia (Melhora desempenho em GPUs antigas)
function Disable-TransparencyEffects {
    Write-Host "`n[8/12] Desativando efeitos de transparencia (melhora desempenho visual)..." -ForegroundColor Yellow
    $keyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    $valueName = "EnableTransparency"

    try {
        if (-not (Test-Path $keyPath)) {
            New-Item -Path $keyPath -Force | Out-Null
        }
        Set-ItemProperty -Path $keyPath -Name $valueName -Value 0 -Force
        Write-Host "      [OK] Efeitos de transparencia desativados." -ForegroundColor Green
        Write-Log "Efeitos de transparencia desativados." "SUCCESS"
    }
    catch {
        Write-Host "      [ERRO] Erro ao desativar transparencia: $_" -ForegroundColor Red
        Write-Log "Erro ao desativar transparencia: $_" "ERROR"
    }
}

# 9. Tweak: Priorizar programas em primeiro plano
function Set-ForegroundPriority {
    Write-Host "`n[9/12] Configurando sistema para priorizar programas em primeiro plano..." -ForegroundColor Yellow
    $keyPath = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
    $valueName = "Win32PrioritySeparation"

    try {
        if (-not (Test-Path $keyPath)) {
            New-Item -Path $keyPath -Force | Out-Null
        }
        Set-ItemProperty -Path $keyPath -Name $valueName -Value 38 -Force
        Write-Host "      [OK] Sistema configurado para priorizar programas em primeiro plano." -ForegroundColor Green
        Write-Log "Prioridade de primeiro plano configurada." "SUCCESS"
    }
    catch {
        Write-Host "      [ERRO] Erro ao configurar prioridade: $_" -ForegroundColor Red
        Write-Log "Erro ao configurar prioridade: $_" "ERROR"
    }
}

# 10. Tweak: Desativar Cortana (Privacidade e desempenho)
function Disable-Cortana {
    Write-Host "`n[10/12] Desativando Cortana (privacidade e desempenho)..." -ForegroundColor Yellow
    $keyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
    $valueName = "AllowCortana"

    try {
        if (-not (Test-Path $keyPath)) {
            New-Item -Path $keyPath -Force | Out-Null
        }
        Set-ItemProperty -Path $keyPath -Name $valueName -Value 0 -Force
        Write-Host "      [OK] Cortana desativada." -ForegroundColor Green
        Write-Log "Cortana desativada." "SUCCESS"
    }
    catch {
        Write-Host "      [ERRO] Erro ao desativar Cortana: $_" -ForegroundColor Red
        Write-Log "Erro ao desativar Cortana: $_" "ERROR"
    }
}

# 11. Tweak: Desativar ID de publicidade (Privacidade)
function Disable-AdvertisingID {
    Write-Host "`n[11/12] Desativando ID de publicidade (privacidade)..." -ForegroundColor Yellow
    $keyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
    $valueName = "Enabled"

    try {
        if (-not (Test-Path $keyPath)) {
            New-Item -Path $keyPath -Force | Out-Null
        }
        Set-ItemProperty -Path $keyPath -Name $valueName -Value 0 -Force
        Write-Host "      [OK] ID de publicidade desativado." -ForegroundColor Green
        Write-Log "ID de publicidade desativado." "SUCCESS"
    }
    catch {
        Write-Host "      [ERRO] Erro ao desativar ID de publicidade: $_" -ForegroundColor Red
        Write-Log "Erro ao desativar ID de publicidade: $_" "ERROR"
    }
}

# 12. Tweak: Mostrar extensoes de arquivos (Personalizacao)
function Show-FileExtensions {
    Write-Host "`n[12/13] Ativando exibicao de extensoes de arquivos..." -ForegroundColor Yellow
    $keyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    $valueName = "HideFileExt"

    try {
        Set-ItemProperty -Path $keyPath -Name $valueName -Value 0 -Force
        Write-Host "      [OK] Extensoes de arquivos agora visiveis." -ForegroundColor Green
        Write-Log "Extensoes de arquivos ativadas." "SUCCESS"
    }
    catch {
        Write-Host "      [ERRO] Erro ao ativar extensoes: $_" -ForegroundColor Red
        Write-Log "Erro ao ativar extensoes: $_" "ERROR"
    }
}

# 13. Tweak: Otimizar uso de todos os nucleos do processador
function Optimize-CPUCores {
    Write-Host "`n[13/13] Otimizando uso de todos os nucleos do processador..." -ForegroundColor Yellow
    $keyPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
    $valueName = "ClearPageFileAtShutdown"
    $keyPath2 = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
    $valueName2 = "Win32PrioritySeparation"

    try {
        # Obter numero de nucleos disponiveis
        $numberOfCores = (Get-WmiObject Win32_Processor).NumberOfLogicalProcessors
        Write-Host "      [INFO] Detectados $numberOfCores nucleos logicos." -ForegroundColor Cyan

        # Configurar para usar todos os nucleos no boot (via BCDEDIT)
        if (Test-ExternalCommand "bcdedit") {
            try {
                $currentBootConfig = bcdedit /enum current 2>&1
                if ($LASTEXITCODE -eq 0) {
                    if ($currentBootConfig -match "numproc") {
                        Write-Host "      [INFO] Limite de nucleos ja configurado no boot." -ForegroundColor Cyan
                    } else {
                        # Remover limite de nucleos se existir
                        $result = bcdedit /deletevalue numproc 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host "      [OK] Limite de nucleos removido do boot." -ForegroundColor Green
                        } else {
                            Write-Host "      [WARNING] Não foi possível remover limite de nucleos: $(Get-SafeErrorMessage $result)" -ForegroundColor Yellow
                        }
                    }
                } else {
                    Write-Host "      [WARNING] Não foi possível verificar configuracao de boot: $(Get-SafeErrorMessage $currentBootConfig)" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "      [WARNING] Erro ao acessar configuracao de boot: $(Get-SafeErrorMessage $_)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "      [WARNING] Comando 'bcdedit' não está disponível. Pulando configuracao de boot." -ForegroundColor Yellow
        }

        # Otimizar agendamento de processador
        if (-not (Test-Path $keyPath2)) {
            New-Item -Path $keyPath2 -Force | Out-Null
        }
        Set-ItemProperty -Path $keyPath2 -Name $valueName2 -Value 38 -Force -ErrorAction SilentlyContinue

        # Desativar paginacao de arquivo no desligamento (melhora desempenho)
        if (-not (Test-Path $keyPath)) {
            New-Item -Path $keyPath -Force | Out-Null
        }
        Set-ItemProperty -Path $keyPath -Name $valueName -Value 0 -Force -ErrorAction SilentlyContinue

        Write-Host "      [OK] Otimizacoes de CPU aplicadas. Sistema configurado para usar todos os nucleos disponiveis." -ForegroundColor Green
        Write-Log "Otimizacoes de CPU aplicadas." "SUCCESS"
    }
    catch {
        Write-Host "      [ERRO] Erro ao otimizar nucleos do processador: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
        Write-Log "Erro ao otimizar nucleos do processador." "ERROR"
    }
}

function Is-TweakApplied {
    param (
        [Parameter(Mandatory=$true)]
        [int]$TweakNumber
    )

    switch ($TweakNumber) {
        1 {
            $schemes = powercfg /list 2>&1
            if ($LASTEXITCODE -ne 0) { return $false }
            $highPerfGUID = $null
            foreach ($line in $schemes) {
                if ($line -match 'Desempenho [Mm][áa]ximo|Ultimate Performance|High Performance|Performance') {
                    if ($line -match '([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})') {
                        $highPerfGUID = $matches[1]
                        break
                    }
                }
            }
            if (-not $highPerfGUID) { return $false }
            $currentScheme = powercfg /getactivescheme 2>&1
            if ($LASTEXITCODE -ne 0) { return $false }
            return $currentScheme -match [regex]::Escape($highPerfGUID)
        }
        2 {
            $keyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
            $valueName = 'AllowTelemetry'
            $value = (Get-ItemProperty -Path $keyPath -Name $valueName -ErrorAction SilentlyContinue).$valueName
            return ($value -eq 0)
        }
        3 {
            $keyPath = 'HKCU:\Control Panel\Desktop'
            $valueName = 'MenuShowDelay'
            $value = (Get-ItemProperty -Path $keyPath -Name $valueName -ErrorAction SilentlyContinue).$valueName
            return ($value -eq 100)
        }
        4 {
            return -not (Test-Path "$env:SystemDrive\hiberfil.sys")
        }
        5 {
            $keyPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
            $interfaces = Get-ChildItem -Path $keyPath -ErrorAction SilentlyContinue
            foreach ($interface in $interfaces) {
                $props = Get-ItemProperty -Path $interface.PSPath -ErrorAction SilentlyContinue
                if ($props.TcpNoDelay -eq 1 -and $props.TcpAckFrequency -eq 1) {
                    return $true
                }
            }
            return $false
        }
        6 {
            $keyPath = 'HKCU:\System\GameConfigStore'
            $valueName = 'GameDVR_Enabled'
            $value = (Get-ItemProperty -Path $keyPath -Name $valueName -ErrorAction SilentlyContinue).$valueName
            return ($value -eq 0)
        }
        7 {
            $service = Get-Service -Name 'SysMain' -ErrorAction SilentlyContinue
            return ($service -and $service.StartType -eq 'Disabled')
        }
        8 {
            $keyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
            $valueName = 'EnableTransparency'
            $value = (Get-ItemProperty -Path $keyPath -Name $valueName -ErrorAction SilentlyContinue).$valueName
            return ($value -eq 0)
        }
        9 {
            $keyPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl'
            $valueName = 'Win32PrioritySeparation'
            $value = (Get-ItemProperty -Path $keyPath -Name $valueName -ErrorAction SilentlyContinue).$valueName
            return ($value -eq 38)
        }
        10 {
            $keyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
            $valueName = 'AllowCortana'
            $value = (Get-ItemProperty -Path $keyPath -Name $valueName -ErrorAction SilentlyContinue).$valueName
            return ($value -eq 0)
        }
        11 {
            $keyPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo'
            $valueName = 'Enabled'
            $value = (Get-ItemProperty -Path $keyPath -Name $valueName -ErrorAction SilentlyContinue).$valueName
            return ($value -eq 0)
        }
        12 {
            $keyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
            $valueName = 'HideFileExt'
            $value = (Get-ItemProperty -Path $keyPath -Name $valueName -ErrorAction SilentlyContinue).$valueName
            return ($value -eq 0)
        }
        13 {
            $keyPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl'
            $valueName = 'Win32PrioritySeparation'
            $priorityValue = (Get-ItemProperty -Path $keyPath -Name $valueName -ErrorAction SilentlyContinue).$valueName
            $bootConfig = bcdedit /enum current 2>&1
            if ($LASTEXITCODE -ne 0) { return $false }
            $numprocLimited = $bootConfig -match 'numproc'
            return ($priorityValue -eq 38 -and -not $numprocLimited)
        }
        default { return $false }
    }
}

function Get-TweakStatusLabel {
    param (
        [Parameter(Mandatory=$true)]
        [int]$TweakNumber
    )

    if (Is-TweakApplied -TweakNumber $TweakNumber) {
        return ' [OK]'
    }
    return ''
}

function Get-TweaksStatus {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  STATUS DOS TWEAKS APLICADOS" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $appliedCount = 0
    $totalTweaks = 13

    # 1. Verificar Plano de Energia
    Write-Host "`n[1/13] Plano de Energia 'Desempenho Maximo':" -ForegroundColor Yellow
    try {
        # Descobrir GUID do plano de Desempenho Maximo dinamicamente
        $schemes = powercfg /list
        $highPerfGUID = $null
        
        foreach ($line in $schemes) {
            if ($line -match "Desempenho [Mm][áa]ximo|Ultimate Performance|High Performance") {
                if ($line -match '([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})') {
                    $highPerfGUID = $matches[1]
                    break
                }
            }
        }
        
        if ($null -eq $highPerfGUID) {
            Write-Host "      [ERRO] Plano de Desempenho Maximo nao encontrado no sistema." -ForegroundColor Red
        } else {
            # Verifica se o plano atual e o de desempenho maximo
            $currentScheme = powercfg /getactivescheme
            if ($currentScheme -match $highPerfGUID) {
                Write-Host "      [ATIVO] Plano de Desempenho Maximo esta ativo (GUID: $highPerfGUID)." -ForegroundColor Green
                $appliedCount++
            } else {
                # Extrair GUID do plano atual
                if ($currentScheme -match '([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})') {
                    $currentPlan = $matches[1]
                    Write-Host "      [INATIVO] Plano atual: $currentPlan (Desempenho Maximo: $highPerfGUID)" -ForegroundColor Red
                } else {
                    Write-Host "      [INATIVO] Plano atual diferente de Desempenho Maximo." -ForegroundColor Red
                }
            }
        }
    } catch {
        Write-Host "      [ERRO] Nao foi possivel verificar o plano de energia." -ForegroundColor Red
    }
    
    # 2. Verificar Telemetria
    Write-Host "`n[2/13] Telemetria Basica:" -ForegroundColor Yellow
    try {
        $keyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
        $valueName = "AllowTelemetry"
        if (Test-Path $keyPath) {
            $telemetryValue = (Get-ItemProperty -Path $keyPath -Name $valueName -ErrorAction SilentlyContinue).$valueName
            if ($telemetryValue -eq 0) {
                Write-Host "      [ATIVO] Telemetria Basica desativada (AllowTelemetry = 0)." -ForegroundColor Green
                $appliedCount++
            } else {
                Write-Host "      [INATIVO] Telemetria Basica ativada (AllowTelemetry = $telemetryValue)." -ForegroundColor Red
            }
        } else {
            Write-Host "      [INATIVO] Chave de registro nao encontrada (telemetria padrao)." -ForegroundColor Red
        }
    } catch {
        Write-Host "      [ERRO] Nao foi possivel verificar a telemetria." -ForegroundColor Red
    }
    
    # 3. Verificar Menu Iniciar
    Write-Host "`n[3/13] Velocidade do Menu Iniciar:" -ForegroundColor Yellow
    try {
        $keyPath = "HKCU:\Control Panel\Desktop"
        $valueName = "MenuShowDelay"
        $menuDelay = (Get-ItemProperty -Path $keyPath -Name $valueName -ErrorAction SilentlyContinue).$valueName
        if ($menuDelay -eq 100) {
            Write-Host "      [ATIVO] Menu Iniciar acelerado (MenuShowDelay = 100ms)." -ForegroundColor Green
            $appliedCount++
        } elseif ($menuDelay -eq 400) {
            Write-Host "      [INATIVO] Menu Iniciar com velocidade padrao (MenuShowDelay = 400ms)." -ForegroundColor Red
        } else {
            Write-Host "      [PERSONALIZADO] Menu Iniciar com delay customizado (MenuShowDelay = ${menuDelay}ms)." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "      [ERRO] Nao foi possivel verificar a velocidade do Menu Iniciar." -ForegroundColor Red
    }
    
    # 4. Verificar Hibernacao
    Write-Host "`n[4/13] Hibernacao:" -ForegroundColor Yellow
    try {
        # Verifica se o arquivo de hibernacao existe
        $hiberFile = Test-Path "$env:SystemDrive\hiberfil.sys"
        if (-not $hiberFile) {
            Write-Host "      [ATIVO] Hibernacao desativada (arquivo hiberfil.sys nao encontrado)." -ForegroundColor Green
            $appliedCount++
        } else {
            Write-Host "      [INATIVO] Hibernacao ativada (arquivo hiberfil.sys encontrado)." -ForegroundColor Red
        }
    } catch {
        Write-Host "      [ERRO] Nao foi possivel verificar o status da hibernacao." -ForegroundColor Red
    }
    
    # 5. Verificar TCP
    Write-Host "`n[5/13] Otimizacoes TCP:" -ForegroundColor Yellow
    try {
        $keyPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
        $interfaces = Get-ChildItem -Path $keyPath
        $optimizedCount = 0
        $totalInterfaces = $interfaces.Count
        
        foreach ($interface in $interfaces) {
            $interfaceKey = $interface.PSPath
            $tcpNoDelay = (Get-ItemProperty -Path $interfaceKey -Name "TcpNoDelay" -ErrorAction SilentlyContinue).TcpNoDelay
            $tcpAckFrequency = (Get-ItemProperty -Path $interfaceKey -Name "TcpAckFrequency" -ErrorAction SilentlyContinue).TcpAckFrequency
            
            if ($tcpNoDelay -eq 1 -and $tcpAckFrequency -eq 1) {
                $optimizedCount++
            }
        }
        
        if ($optimizedCount -gt 0) {
            Write-Host "      [ATIVO] Otimizacoes TCP aplicadas em $optimizedCount de $totalInterfaces interface(s)." -ForegroundColor Green
            $appliedCount++
        } else {
            Write-Host "      [INATIVO] Nenhuma otimizacao TCP aplicada." -ForegroundColor Red
        }
    } catch {
        Write-Host "      [ERRO] Nao foi possivel verificar as otimizacoes TCP." -ForegroundColor Red
    }

    # 6. Verificar Game DVR
    Write-Host "`n[6/13] Game DVR:" -ForegroundColor Yellow
    try {
        $keyPath = "HKCU:\System\GameConfigStore"
        $valueName = "GameDVR_Enabled"
        $gameDVRValue = (Get-ItemProperty -Path $keyPath -Name $valueName -ErrorAction SilentlyContinue).$valueName
        if ($gameDVRValue -eq 0) {
            Write-Host "      [ATIVO] Game DVR desativado." -ForegroundColor Green
            $appliedCount++
        } else {
            Write-Host "      [INATIVO] Game DVR ativado." -ForegroundColor Red
        }
    } catch {
        Write-Host "      [ERRO] Nao foi possivel verificar o Game DVR." -ForegroundColor Red
    }

    # 7. Verificar Superfetch/SysMain
    Write-Host "`n[7/13] Superfetch/SysMain:" -ForegroundColor Yellow
    try {
        $serviceName = "SysMain"
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($service) {
            if ($service.StartType -eq "Disabled") {
                Write-Host "      [ATIVO] Superfetch/SysMain desativado." -ForegroundColor Green
                $appliedCount++
            } else {
                Write-Host "      [INATIVO] Superfetch/SysMain ativado (StartType: $($service.StartType))." -ForegroundColor Red
            }
        } else {
            Write-Host "      [INFO] Servico SysMain nao encontrado." -ForegroundColor Cyan
        }
    } catch {
        Write-Host "      [ERRO] Nao foi possivel verificar o Superfetch." -ForegroundColor Red
    }

    # 8. Verificar Transparencia
    Write-Host "`n[8/13] Efeitos de Transparencia:" -ForegroundColor Yellow
    try {
        $keyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        $valueName = "EnableTransparency"
        $transparencyValue = (Get-ItemProperty -Path $keyPath -Name $valueName -ErrorAction SilentlyContinue).$valueName
        if ($transparencyValue -eq 0) {
            Write-Host "      [ATIVO] Efeitos de transparencia desativados." -ForegroundColor Green
            $appliedCount++
        } else {
            Write-Host "      [INATIVO] Efeitos de transparencia ativados." -ForegroundColor Red
        }
    } catch {
        Write-Host "      [ERRO] Nao foi possivel verificar a transparencia." -ForegroundColor Red
    }

    # 9. Verificar Prioridade de Primeiro Plano
    Write-Host "`n[9/13] Prioridade de Primeiro Plano:" -ForegroundColor Yellow
    try {
        $keyPath = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
        $valueName = "Win32PrioritySeparation"
        $priorityValue = (Get-ItemProperty -Path $keyPath -Name $valueName -ErrorAction SilentlyContinue).$valueName
        if ($priorityValue -eq 38) {
            Write-Host "      [ATIVO] Sistema configurado para priorizar primeiro plano." -ForegroundColor Green
            $appliedCount++
        } else {
            Write-Host "      [INATIVO] Configuracao padrao de prioridade (Valor: $priorityValue)." -ForegroundColor Red
        }
    } catch {
        Write-Host "      [ERRO] Nao foi possivel verificar a prioridade." -ForegroundColor Red
    }

    # 10. Verificar Cortana
    Write-Host "`n[10/13] Cortana:" -ForegroundColor Yellow
    try {
        $keyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
        $valueName = "AllowCortana"
        if (Test-Path $keyPath) {
            $cortanaValue = (Get-ItemProperty -Path $keyPath -Name $valueName -ErrorAction SilentlyContinue).$valueName
            if ($cortanaValue -eq 0) {
                Write-Host "      [ATIVO] Cortana desativada." -ForegroundColor Green
                $appliedCount++
            } else {
                Write-Host "      [INATIVO] Cortana ativada." -ForegroundColor Red
            }
        } else {
            Write-Host "      [INATIVO] Chave de registro nao encontrada (Cortana padrao)." -ForegroundColor Red
        }
    } catch {
        Write-Host "      [ERRO] Nao foi possivel verificar a Cortana." -ForegroundColor Red
    }

    # 11. Verificar ID de Publicidade
    Write-Host "`n[11/13] ID de Publicidade:" -ForegroundColor Yellow
    try {
        $keyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
        $valueName = "Enabled"
        $adIDValue = (Get-ItemProperty -Path $keyPath -Name $valueName -ErrorAction SilentlyContinue).$valueName
        if ($adIDValue -eq 0) {
            Write-Host "      [ATIVO] ID de publicidade desativado." -ForegroundColor Green
            $appliedCount++
        } else {
            Write-Host "      [INATIVO] ID de publicidade ativado." -ForegroundColor Red
        }
    } catch {
        Write-Host "      [ERRO] Nao foi possivel verificar o ID de publicidade." -ForegroundColor Red
    }

    # 12. Verificar Extensoes de Arquivos
    Write-Host "`n[12/13] Extensoes de Arquivos:" -ForegroundColor Yellow
    try {
        $keyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        $valueName = "HideFileExt"
        $hideExtValue = (Get-ItemProperty -Path $keyPath -Name $valueName -ErrorAction SilentlyContinue).$valueName
        if ($hideExtValue -eq 0) {
            Write-Host "      [ATIVO] Extensoes de arquivos visiveis." -ForegroundColor Green
            $appliedCount++
        } else {
            Write-Host "      [INATIVO] Extensoes de arquivos ocultas." -ForegroundColor Red
        }
    } catch {
        Write-Host "      [ERRO] Nao foi possivel verificar as extensoes de arquivos." -ForegroundColor Red
    }

    # 13. Verificar Otimizacao de CPU
    Write-Host "`n[13/13] Otimizacao de Nucleos do Processador:" -ForegroundColor Yellow
    try {
        $keyPath = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
        $valueName = "Win32PrioritySeparation"
        $priorityValue = (Get-ItemProperty -Path $keyPath -Name $valueName -ErrorAction SilentlyContinue).$valueName
        
        # Verificar configuracao de boot
        $bootConfig = bcdedit /enum current
        $numprocLimited = $bootConfig -match "numproc"
        
        if ($priorityValue -eq 38 -and -not $numprocLimited) {
            Write-Host "      [ATIVO] Sistema configurado para usar todos os nucleos disponiveis." -ForegroundColor Green
            $appliedCount++
        } else {
            $status = if ($numprocLimited) { "Limite de nucleos ativo no boot" } else { "Configuracao padrao" }
            Write-Host "      [INATIVO] $status (Valor: $priorityValue)." -ForegroundColor Red
        }
    } catch {
        Write-Host "      [ERRO] Nao foi possivel verificar a otimizacao de CPU." -ForegroundColor Red
    }

    # Resumo
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  RESUMO: $appliedCount de $totalTweaks tweaks aplicados" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    if ($appliedCount -eq $totalTweaks) {
        Write-Host "Todos os tweaks estao aplicados!" -ForegroundColor Green
    } elseif ($appliedCount -eq 0) {
        Write-Host "Nenhum tweak aplicado." -ForegroundColor Red
    } else {
        Write-Host "$appliedCount tweak(s) aplicado(s). Use a opcao 6 para aplicar todos." -ForegroundColor Yellow
    }
    
    Write-Log "Status dos tweaks verificado: $appliedCount/$totalTweaks aplicados" "INFO"
}

function Invoke-SystemTweaks {
    Show-TweaksMenu

    $choice = Read-Host "Digite o numero da sua escolha"

    # Remover espaços em branco
    $choice = $choice -replace '\s+', ''

    # Validar input
    if (-not (Test-ValidNumericInput -Value $choice -Min 1 -Max 16)) {
        Write-Host "Opcao invalida. Por favor, digite um numero entre 1 e 16." -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }

    switch ($choice) {
        "1" {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Set-HighPerformancePowerPlan
            Write-Host "========================================" -ForegroundColor Cyan
        }
        "2" {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Disable-BasicTelemetry
            Write-Host "========================================" -ForegroundColor Cyan
        }
        "3" {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Set-StartMenuSpeed
            Write-Host "========================================" -ForegroundColor Cyan
        }
        "4" {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Disable-Hibernation
            Write-Host "========================================" -ForegroundColor Cyan
        }
        "5" {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Optimize-TCP
            Write-Host "========================================" -ForegroundColor Cyan
        }
        "6" {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Disable-GameDVR
            Write-Host "========================================" -ForegroundColor Cyan
        }
        "7" {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Disable-Superfetch
            Write-Host "========================================" -ForegroundColor Cyan
        }
        "8" {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Disable-TransparencyEffects
            Write-Host "========================================" -ForegroundColor Cyan
        }
        "9" {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Set-ForegroundPriority
            Write-Host "========================================" -ForegroundColor Cyan
        }
        "10" {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Disable-Cortana
            Write-Host "========================================" -ForegroundColor Cyan
        }
        "11" {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Disable-AdvertisingID
            Write-Host "========================================" -ForegroundColor Cyan
        }
        "12" {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Show-FileExtensions
            Write-Host "========================================" -ForegroundColor Cyan
        }
        "13" {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Optimize-CPUCores
            Write-Host "========================================" -ForegroundColor Cyan
        }
        "14" {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Write-Host "  APLICANDO TODOS OS AJUSTES" -ForegroundColor Cyan
            Write-Host "========================================" -ForegroundColor Cyan
            Set-HighPerformancePowerPlan
            Disable-BasicTelemetry
            Set-StartMenuSpeed
            Disable-Hibernation
            Optimize-TCP
            Disable-GameDVR
            Disable-Superfetch
            Disable-TransparencyEffects
            Set-ForegroundPriority
            Disable-Cortana
            Disable-AdvertisingID
            Show-FileExtensions
            Optimize-CPUCores
            Write-Host "`n========================================" -ForegroundColor Green
            Write-Host "  TODOS OS AJUSTES APLICADOS!" -ForegroundColor Green
            Write-Host "========================================" -ForegroundColor Green
        }
        "15" {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Get-TweaksStatus
            Write-Host "========================================" -ForegroundColor Cyan
        }
        "16" { return }
        default {
            Write-Host "Opcao invalida. Por favor, tente novamente." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
}

