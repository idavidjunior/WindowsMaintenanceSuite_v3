<#
.SYNOPSIS
    Módulo para aplicar ajustes (tweaks) de sistema no Windows.
.DESCRIPTION
    Este módulo contém funções para otimizar o desempenho, privacidade e experiência do usuário
    no Windows, com a opção de reverter as alterações.
#>

# Função auxiliar para backup de chave de registro
function Backup-RegistryKey {
    param (
        [string]$KeyPath,
        [string]$BackupName
    )
    $BackupDir = "C:\WMS_RegistryBackups"
    if (-not (Test-Path -Path $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    }
    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $BackupFile = Join-Path -Path $BackupDir -ChildPath "RegistryBackup_$(($KeyPath -replace '[\\/:]', '_') | ForEach-Object { $_.Replace(' ', '') })_$BackupName_$Timestamp.reg"
    
    try {
        reg export $KeyPath "$BackupFile" /y | Out-Null
        Write-Host "Backup da chave de registro '$KeyPath' salvo em: $BackupFile" -ForegroundColor DarkGreen
        return $BackupFile
    }
    catch {
        Write-Host "Erro ao fazer backup da chave de registro '$KeyPath': $_" -ForegroundColor Red
        return $null
    }
}

# 1. Tweak: Ativar Plano de Energia "Desempenho Maximo"
function Set-HighPerformancePowerPlan {
    Write-Host "`n[1/5] Ativando Plano de Energia 'Desempenho Maximo'..." -ForegroundColor Yellow
    try {
        # GUID para Desempenho Maximo (pode estar oculto)
        $HighPerformanceGUID = "4d3a011a-356a-464a-874e-417127110166"
        
        # Verifica se o plano ja existe ou se precisa ser importado/ativado
        $currentPlan = (powercfg /getactivescheme).Split(" ")[3]
        if ($currentPlan -ne $HighPerformanceGUID) {
            # Tenta ativar o plano
            powercfg /setactive $HighPerformanceGUID | Out-Null
            Write-Host "      [OK] Plano de energia 'Desempenho Maximo' ativado com sucesso." -ForegroundColor Green
            Write-Log "Plano de energia 'Desempenho Maximo' ativado." "SUCCESS"
        } else {
            Write-Host "      [INFO] Plano de energia 'Desempenho Maximo' ja estava ativo." -ForegroundColor Cyan
            Write-Log "Plano de energia 'Desempenho Maximo' ja estava ativo." "INFO"
        }
    }
    catch {
        Write-Host "      [ERRO] Erro ao ativar plano de energia: $_" -ForegroundColor Red
        Write-Log "Erro ao ativar plano de energia: $_" "ERROR"
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
    Write-Host "`n[5/5] Otimizando TCP (Desativar Nagle's Algorithm)..." -ForegroundColor Yellow
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

function Get-TweaksStatus {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  STATUS DOS TWEAKS APLICADOS" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    $appliedCount = 0
    $totalTweaks = 5
    
    # 1. Verificar Plano de Energia
    Write-Host "`n[1/5] Plano de Energia 'Desempenho Maximo':" -ForegroundColor Yellow
    try {
        $HighPerformanceGUID = "4d3a011a-356a-464a-874e-417127110166"
        $schemeOutput = powercfg /getactivescheme
        if ($schemeOutput -match '([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})') {
            $currentPlan = $matches[1]
            if ($currentPlan -eq $HighPerformanceGUID) {
                Write-Host "      [ATIVO] Plano de Desempenho Maximo esta ativo." -ForegroundColor Green
                $appliedCount++
            } else {
                Write-Host "      [INATIVO] Plano atual: $currentPlan" -ForegroundColor Red
            }
        } else {
            Write-Host "      [ERRO] Nao foi possivel extrair GUID do plano atual." -ForegroundColor Red
        }
    } catch {
        Write-Host "      [ERRO] Nao foi possivel verificar o plano de energia." -ForegroundColor Red
    }
    
    # 2. Verificar Telemetria
    Write-Host "`n[2/5] Telemetria Basica:" -ForegroundColor Yellow
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
    Write-Host "`n[3/5] Velocidade do Menu Iniciar:" -ForegroundColor Yellow
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
    Write-Host "`n[4/5] Hibernacao:" -ForegroundColor Yellow
    try {
        $hiberStatus = powercfg /h | Select-String "hibernacao"
        if ($hiberStatus -match "desativada" -or $hiberStatus -match "disabled") {
            Write-Host "      [ATIVO] Hibernacao desativada." -ForegroundColor Green
            $appliedCount++
        } else {
            Write-Host "      [INATIVO] Hibernacao ativada." -ForegroundColor Red
        }
    } catch {
        Write-Host "      [ERRO] Nao foi possivel verificar o status da hibernacao." -ForegroundColor Red
    }
    
    # 5. Verificar TCP
    Write-Host "`n[5/5] Otimizacoes TCP:" -ForegroundColor Yellow
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
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  AJUSTES DE SISTEMA (TWEAKS)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "`nSelecione os ajustes que deseja aplicar:"
    Write-Host "  1. Ativar Plano de Energia 'Desempenho Maximo'"
    Write-Host "  2. Desativar Telemetria Basica"
    Write-Host "  3. Acelerar Resposta do Menu Iniciar"
    Write-Host "  4. Desativar Hibernacao (Libera espaco em disco)"
    Write-Host "  5. Otimizar TCP (Desativar Nagle's Algorithm)"
    Write-Host "  6. Aplicar TODOS os ajustes acima"
    Write-Host "  7. Verificar status dos tweaks aplicados"
    Write-Host "  8. Voltar ao Menu Principal"
    Write-Host "`n========================================" -ForegroundColor Cyan

    $choice = Read-Host "Digite o numero da sua escolha"

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
            Write-Host "  APLICANDO TODOS OS AJUSTES" -ForegroundColor Cyan
            Write-Host "========================================" -ForegroundColor Cyan
            Set-HighPerformancePowerPlan
            Disable-BasicTelemetry
            Set-StartMenuSpeed
            Disable-Hibernation
            Optimize-TCP
            Write-Host "`n========================================" -ForegroundColor Green
            Write-Host "  TODOS OS AJUSTES APLICADOS!" -ForegroundColor Green
            Write-Host "========================================" -ForegroundColor Green
        }
        "7" {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Get-TweaksStatus
            Write-Host "========================================" -ForegroundColor Cyan
        }
        "8" { return }
        default {
            Write-Host "Opcao invalida. Por favor, tente novamente." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
}

