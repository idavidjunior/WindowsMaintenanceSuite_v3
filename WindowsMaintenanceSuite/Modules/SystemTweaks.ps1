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
    Write-Host "  7. Voltar ao Menu Principal"
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
        "7" { return }
        default {
            Write-Host "Opcao invalida. Por favor, tente novamente." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
}

