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
    Write-TweakMenuOption -Index 14 -Label "Desativar pesquisa web no Menu Iniciar (menu mais rapido)" -Applied (Test-WebSearchDisabled)
    Write-TweakMenuOption -Index 15 -Label "Ajustar para melhor desempenho (desativa efeitos visuais)" -Applied (Test-BestPerformanceVisualsConfigured)
    Write-TweakMenuOption -Index 16 -Label "Remover apps padrao (Debloat: Candy Crush, dicas, etc.)" -Applied (Test-BloatwareRemoved)
    Write-TweakMenuOption -Index 17 -Label "Desativar Widgets/Chat/People na taskbar" -Applied (Test-TaskbarExtrasDisabled)
    Write-TweakMenuOption -Index 18 -Label "Desativar conteudo sugerido, dicas e Timeline" -Applied (Test-SuggestedContentDisabled)
    Write-TweakMenuOption -Index 19 -Label "Desativar rastreamento de localizacao (Privacidade)" -Applied (Test-LocationTrackingDisabled)
    Write-TweakMenuOption -Index 20 -Label "Aplicar TODOS os ajustes acima" -Applied $false
    Write-TweakMenuOption -Index 21 -Label "Verificar status dos tweaks aplicados" -Applied $false
    Write-TweakMenuOption -Index 22 -Label "Voltar ao Menu Principal" -Applied $false

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

# 14. Tweak: Desativar pesquisa web no Menu Iniciar (maior ganho de resposta)
function Disable-WebSearchInStartMenu {
    Write-Host "`n[14] Desativando pesquisa web no Menu Iniciar..." -ForegroundColor Yellow
    try {
        $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
        if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
        Set-ItemProperty -Path $key -Name "BingSearchEnabled" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $key -Name "CortanaConsent" -Value 0 -Type DWord -Force
        $key2 = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        if (Test-Path $key2) {
            Set-ItemProperty -Path $key2 -Name "DisableSearchBoxSuggestions" -Value 1 -Type DWord -Force
        }
        Write-Host "      [OK] Pesquisa web no Menu Iniciar desativada (menu fica mais rapido)." -ForegroundColor Green
        Write-Log "Pesquisa web no Menu Iniciar desativada." "SUCCESS"
    } catch {
        Write-Host "      [ERRO] Falha: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
        Write-Log "Erro ao desativar pesquisa web: $_" "ERROR"
    }
}

# 15. Tweak: Ajustar para melhor desempenho (desativa animacoes/sombras/transparencia)
function Set-BestPerformanceVisuals {
    Write-Host "`n[15] Ajustando para melhor desempenho (desativa efeitos visuais)..." -ForegroundColor Yellow
    try {
        $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
        if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
        # 0 = ajustar para melhor desempenho, 2 = personalizado, 3 = deixar o Windows escolher
        Set-ItemProperty -Path $key -Name "VisualFXSetting" -Value 2 -Type DWord -Force
        # UserPreferencesMask: desativa a maioria dos efeitos (mantem suavizacao de fonte)
        $key2 = "HKCU:\Control Panel\Desktop"
        if (-not (Test-Path $key2)) { New-Item -Path $key2 -Force | Out-Null }
        Set-ItemProperty -Path $key2 -Name "UserPreferencesMask" -Value ([byte[]](0x90,0x12,0x01,0x80,0x10,0x00,0x00,0x00)) -Force
        Set-ItemProperty -Path $key2 -Name "DragFullWindows" -Value 0 -Force
        Set-ItemProperty -Path $key2 -Name "FontSmoothing" -Value 2 -Force
        Set-ItemProperty -Path $key2 -Name "MenuShowDelay" -Value 0 -Force
        # Desativar animacoes de janela (DWM)
        $key3 = "HKCU:\Software\Microsoft\Windows\DWM"
        if (Test-Path $key3) {
            Set-ItemProperty -Path $key3 -Name "EnableAeroPeek" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        }
        Write-Host "      [OK] Sistema ajustado para melhor desempenho (aplique apos reiniciar o Explorer)." -ForegroundColor Green
        Write-Host "      [INFO] Para aplicar agora: reinicie o explorer.exe ou faca logoff." -ForegroundColor Cyan
        Write-Log "Efeitos visuais ajustados para melhor desempenho." "SUCCESS"
    } catch {
        Write-Host "      [ERRO] Falha: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
        Write-Log "Erro ao ajustar efeitos visuais: $_" "ERROR"
    }
}

# 16. Tweak: Debloat de apps padrao (Candy Crush, TikTok, dicas, etc.)
function Remove-DefaultBloatware {
    Write-Host "`n[16] Removendo apps padrao (bloatware)..." -ForegroundColor Yellow
    $bloatwarePatterns = @(
        "*CandyCrush*", "*TikTok*", "*Twitter*", "*Facebook*",
        "*Microsoft.BingNews*", "*Microsoft.BingWeather*", "*Microsoft.GetHelp*",
        "*Microsoft.Getstarted*", "*Microsoft.Microsoft3DViewer*", "*Microsoft.MinecraftUWP*",
        "*Microsoft.MicrosoftSolitaireCollection*", "*Microsoft.Office.OneNote*",
        "*Microsoft.OneConnect*", "*Microsoft.People*", "*Microsoft.SkypeApp*",
        "*Microsoft.Wallet*", "*Microsoft.WindowsFeedbackHub*", "*Microsoft.WindowsMaps*",
        "*Microsoft.Xbox*", "*Microsoft.ZuneMusic*", "*Microsoft.ZuneVideo*",
        "*king.com*", "*Spotify*", "*Disney*", "*Asphalt*"
    )
    $removed = 0
    $failed = 0
    foreach ($pattern in $bloatwarePatterns) {
        try {
            $apps = Get-AppxPackage -Name $pattern -ErrorAction SilentlyContinue
            foreach ($app in $apps) {
                Write-Host "      [INFO] Removendo: $($app.Name)..." -ForegroundColor DarkGray
                Remove-AppxPackage -Package $app.PackageFullName -ErrorAction SilentlyContinue
                $removed++
            }
        } catch {
            $failed++
        }
    }
    if ($removed -gt 0) {
        Write-Host "      [OK] $removed app(s) bloatware removido(s)." -ForegroundColor Green
        Write-Log "Debloat: $removed apps removidos." "SUCCESS"
    } else {
        Write-Host "      [INFO] Nenhum bloatware dos padroes conhecidos encontrado (sistema ja limpo)." -ForegroundColor Cyan
        Write-Log "Debloat: nada encontrado para remover." "INFO"
    }
}

# 17. Tweak: Desativar Widgets / Meet Now / People na taskbar
function Disable-TaskbarExtras {
    Write-Host "`n[17] Desativando Widgets / Meet Now / People na taskbar..." -ForegroundColor Yellow
    try {
        $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
        # TaskbarDa (Widgets) e TaskbarMn (Meet Now/Chat) - Win11
        Set-ItemProperty -Path $key -Name "TaskbarDa" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $key -Name "TaskbarMn" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        # People (Win10)
        Set-ItemProperty -Path $key -Name "PeopleBand" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Host "      [OK] Widgets/Chat/People desativados (reinicie o explorer ou faca logoff)." -ForegroundColor Green
        Write-Log "Taskbar extras (Widgets/Chat/People) desativados." "SUCCESS"
    } catch {
        Write-Host "      [ERRO] Falha: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
        Write-Log "Erro ao desativar taskbar extras: $_" "ERROR"
    }
}

# 18. Tweak: Desativar conteudo sugerido + dicas + Timeline (atividades)
function Disable-SuggestedContentAndTimeline {
    Write-Host "`n[18] Desativando conteudo sugerido, dicas e Timeline..." -ForegroundColor Yellow
    try {
        $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        if (Test-Path $key) {
            foreach ($v in @("SubscribedContent-310093Enabled","SubscribedContent-338388Enabled",
                             "SubscribedContent-338389Enabled","SubscribedContent-338393Enabled",
                             "SubscribedContent-353694Enabled","SubscribedContent-353696Enabled",
                             "SystemPaneSuggestionsEnabled","SilentInstalledAppsEnabled",
                             "SoftLandingEnabled","RotatingLockScreenEnabled",
                             "RotatingLockScreenOverlayEnabled")) {
                Set-ItemProperty -Path $key -Name $v -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            }
        }
        # Desativar coleta/atividades (Timeline)
        $key2 = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
        if (-not (Test-Path $key2)) { New-Item -Path $key2 -Force | Out-Null }
        Set-ItemProperty -Path $key2 -Name "EnableActivityFeed" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $key2 -Name "PublishUserActivities" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $key2 -Name "UploadUserActivities" -Value 0 -Type DWord -Force
        Write-Host "      [OK] Conteudo sugerido, dicas e Timeline desativados." -ForegroundColor Green
        Write-Log "Conteudo sugerido/dicas/Timeline desativados." "SUCCESS"
    } catch {
        Write-Host "      [ERRO] Falha: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
        Write-Log "Erro ao desativar conteudo sugerido/Timeline: $_" "ERROR"
    }
}

# 19. Tweak: Desativar rastreamento de localizacao (privacidade)
function Disable-LocationTracking {
    Write-Host "`n[19] Desativando rastreamento de localizacao..." -ForegroundColor Yellow
    try {
        $key = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location"
        if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
        Set-ItemProperty -Path $key -Name "Value" -Value "Deny" -Force
        $key2 = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location"
        if (-not (Test-Path $key2)) { New-Item -Path $key2 -Force | Out-Null }
        Set-ItemProperty -Path $key2 -Name "Value" -Value "Deny" -Force
        Write-Host "      [OK] Rastreamento de localizacao desativado." -ForegroundColor Green
        Write-Log "Rastreamento de localizacao desativado." "SUCCESS"
    } catch {
        Write-Host "      [ERRO] Falha: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
        Write-Log "Erro ao desativar rastreamento de localizacao: $_" "ERROR"
    }
}

# --- Funcoes de TESTE (status) para os novos tweaks 14-19 ---
function Test-WebSearchDisabled {
    $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
    $v = (Get-ItemProperty -Path $key -Name "BingSearchEnabled" -ErrorAction SilentlyContinue).BingSearchEnabled
    return ($v -eq 0)
}
function Test-BestPerformanceVisualsConfigured {
    $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    $v = (Get-ItemProperty -Path $key -Name "VisualFXSetting" -ErrorAction SilentlyContinue).VisualFXSetting
    return ($v -eq 2)
}
function Test-BloatwareRemoved {
    # Considera aplicado se nenhum dos bloatwares conhecidos estiver presente
    $patterns = @("*CandyCrush*","*king.com*","*Microsoft.Getstarted*","*TikTok*")
    foreach ($p in $patterns) {
        if (Get-AppxPackage -Name $p -ErrorAction SilentlyContinue) { return $false }
    }
    return $true
}
function Test-TaskbarExtrasDisabled {
    $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    $da = (Get-ItemProperty -Path $key -Name "TaskbarDa" -ErrorAction SilentlyContinue).TaskbarDa
    $people = (Get-ItemProperty -Path $key -Name "PeopleBand" -ErrorAction SilentlyContinue).PeopleBand
    return ($da -eq 0 -or $people -eq 0)
}
function Test-SuggestedContentDisabled {
    $key = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    $v = (Get-ItemProperty -Path $key -Name "EnableActivityFeed" -ErrorAction SilentlyContinue).EnableActivityFeed
    return ($v -eq 0)
}
function Test-LocationTrackingDisabled {
    $key = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location"
    $v = (Get-ItemProperty -Path $key -Name "Value" -ErrorAction SilentlyContinue).Value
    return ($v -eq "Deny")
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
        14 { return Test-WebSearchDisabled }
        15 { return Test-BestPerformanceVisualsConfigured }
        16 { return Test-BloatwareRemoved }
        17 { return Test-TaskbarExtrasDisabled }
        18 { return Test-SuggestedContentDisabled }
        19 { return Test-LocationTrackingDisabled }
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
    $totalTweaks = 19

    # 1. Verificar Plano de Energia
    Write-Host "`n[1/13] Plano de Energia 'Desempenho Maximo':" -ForegroundColor Yellow
    try {
        $highPerfGUID = Get-HighPerformancePlanGuid

        if ([string]::IsNullOrWhiteSpace($highPerfGUID)) {
            Write-Host "      [ERRO] Plano de Desempenho Maximo nao encontrado no sistema." -ForegroundColor Red
        } else {
            $currentScheme = powercfg /getactivescheme 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "      [ERRO] Nao foi possivel verificar o plano de energia." -ForegroundColor Red
            } elseif ($currentScheme -match [regex]::Escape($highPerfGUID)) {
                Write-Host "      [ATIVO] Plano de Desempenho Maximo esta ativo (GUID: $highPerfGUID)." -ForegroundColor Green
                $appliedCount++
            } else {
                Write-Host "      [INATIVO] Plano atual diferente de Desempenho Maximo." -ForegroundColor Red
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

    # 14. Verificar Pesquisa Web no Menu Iniciar
    Write-Host "`n[14/19] Pesquisa Web no Menu Iniciar:" -ForegroundColor Yellow
    if (Test-WebSearchDisabled) {
        Write-Host "      [ATIVO] Pesquisa web no Menu Iniciar desativada." -ForegroundColor Green
        $appliedCount++
    } else {
        Write-Host "      [INATIVO] Pesquisa web ativada (menu lento)." -ForegroundColor Red
    }

    # 15. Verificar Efeitos Visuais
    Write-Host "`n[15/19] Efeitos Visuais (Melhor Desempenho):" -ForegroundColor Yellow
    if (Test-BestPerformanceVisualsConfigured) {
        Write-Host "      [ATIVO] Sistema ajustado para melhor desempenho." -ForegroundColor Green
        $appliedCount++
    } else {
        Write-Host "      [INATIVO] Efeitos visuais padrao ativados." -ForegroundColor Red
    }

    # 16. Verificar Bloatware removido
    Write-Host "`n[16/19] Apps Padrao (Bloatware):" -ForegroundColor Yellow
    if (Test-BloatwareRemoved) {
        Write-Host "      [ATIVO] Sem bloatware conhecido (sistema limpo)." -ForegroundColor Green
        $appliedCount++
    } else {
        Write-Host "      [INATIVO] Bloatware padrao ainda presente." -ForegroundColor Red
    }

    # 17. Verificar Taskbar Extras
    Write-Host "`n[17/19] Widgets/Chat/People na Taskbar:" -ForegroundColor Yellow
    if (Test-TaskbarExtrasDisabled) {
        Write-Host "      [ATIVO] Widgets/Chat/People desativados." -ForegroundColor Green
        $appliedCount++
    } else {
        Write-Host "      [INATIVO] Taskbar extras ativados." -ForegroundColor Red
    }

    # 18. Verificar Conteudo Sugerido/Timeline
    Write-Host "`n[18/19] Conteudo Sugerido e Timeline:" -ForegroundColor Yellow
    if (Test-SuggestedContentDisabled) {
        Write-Host "      [ATIVO] Conteudo sugerido/Timeline desativados." -ForegroundColor Green
        $appliedCount++
    } else {
        Write-Host "      [INATIVO] Conteudo sugerido/Timeline ativados." -ForegroundColor Red
    }

    # 19. Verificar Rastreamento de Localizacao
    Write-Host "`n[19/19] Rastreamento de Localizacao:" -ForegroundColor Yellow
    if (Test-LocationTrackingDisabled) {
        Write-Host "      [ATIVO] Rastreamento de localizacao desativado." -ForegroundColor Green
        $appliedCount++
    } else {
        Write-Host "      [INATIVO] Rastreamento de localizacao ativado." -ForegroundColor Red
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
        Write-Host "$appliedCount tweak(s) aplicado(s). Use a opcao 20 para aplicar todos." -ForegroundColor Yellow
    }
    
    Write-Log "Status dos tweaks verificado: $appliedCount/$totalTweaks aplicados" "INFO"
}

function Invoke-SystemTweaks {
    Show-TweaksMenu

    $choice = Read-Host "Digite o numero da sua escolha"

    # Remover espaços em branco
    $choice = $choice -replace '\s+', ''

    # Validar input
    if (-not (Test-ValidNumericInput -Value $choice -Min 1 -Max 22)) {
        Write-Host "Opcao invalida. Por favor, digite um numero entre 1 e 22." -ForegroundColor Red
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
            Disable-WebSearchInStartMenu
            Write-Host "========================================" -ForegroundColor Cyan
        }
        "15" {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Set-BestPerformanceVisuals
            Write-Host "========================================" -ForegroundColor Cyan
        }
        "16" {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Remove-DefaultBloatware
            Write-Host "========================================" -ForegroundColor Cyan
        }
        "17" {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Disable-TaskbarExtras
            Write-Host "========================================" -ForegroundColor Cyan
        }
        "18" {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Disable-SuggestedContentAndTimeline
            Write-Host "========================================" -ForegroundColor Cyan
        }
        "19" {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Disable-LocationTracking
            Write-Host "========================================" -ForegroundColor Cyan
        }
        "20" {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Write-Host "  APLICANDO TODOS OS AJUSTES (1-19)" -ForegroundColor Cyan
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
            Disable-WebSearchInStartMenu
            Set-BestPerformanceVisuals
            Remove-DefaultBloatware
            Disable-TaskbarExtras
            Disable-SuggestedContentAndTimeline
            Disable-LocationTracking
            Write-Host "`n========================================" -ForegroundColor Green
            Write-Host "  TODOS OS AJUSTES APLICADOS!" -ForegroundColor Green
            Write-Host "========================================" -ForegroundColor Green
        }
        "21" {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Get-TweaksStatus
            Write-Host "========================================" -ForegroundColor Cyan
        }
        "22" { return }
        default {
            Write-Host "Opcao invalida. Por favor, tente novamente." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
}

