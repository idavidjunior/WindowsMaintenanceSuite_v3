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

# 1. Tweak: Ativar Plano de Energia "Desempenho Máximo"
function Set-HighPerformancePowerPlan {
    Write-Host "Aplicando Tweak: Ativar Plano de Energia 'Desempenho Máximo'..." -ForegroundColor Cyan
    try {
        # GUID para Desempenho Máximo (pode estar oculto)
        $HighPerformanceGUID = "4d3a011a-356a-464a-874e-417127110166"
        
        # Verifica se o plano já existe ou se precisa ser importado/ativado
        $currentPlan = (powercfg /getactivescheme).Split(" ")[3]
        if ($currentPlan -ne $HighPerformanceGUID) {
            # Tenta ativar o plano
            powercfg /setactive $HighPerformanceGUID | Out-Null
            Write-Host "Plano de energia 'Desempenho Máximo' ativado." -ForegroundColor Green
        } else {
            Write-Host "Plano de energia 'Desempenho Máximo' já está ativo." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "Erro ao ativar plano de energia: $_" -ForegroundColor Red
    }
}

# 2. Tweak: Desativar Telemetria Básica
function Disable-BasicTelemetry {
    Write-Host "Aplicando Tweak: Desativar Telemetria Básica..." -ForegroundColor Cyan
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
        Write-Host "Telemetria Básica desativada (AllowTelemetry = 0). Valor original: $($originalValue -replace '^$', 'Não Existia')" -ForegroundColor Green
    }
    catch {
        Write-Host "Erro ao desativar telemetria básica: $_" -ForegroundColor Red
    }
}

# 3. Tweak: Acelerar Resposta do Menu Iniciar
function SpeedUp-StartMenu {
    Write-Host "Aplicando Tweak: Acelerar Resposta do Menu Iniciar..." -ForegroundColor Cyan
    $keyPath = "HKCU:\Control Panel\Desktop"
    $valueName = "MenuShowDelay"
    $originalValue = $null

    try {
        if ((Get-ItemProperty -Path $keyPath -Name $valueName -ErrorAction SilentlyContinue)) {
            $originalValue = (Get-ItemProperty -Path $keyPath -Name $valueName).$valueName
        }
        
        Set-ItemProperty -Path $keyPath -Name $valueName -Value 100 -Force # Valor padrão é 400
        Write-Host "Atraso do Menu Iniciar ajustado para 100ms. Valor original: $($originalValue -replace '^$', 'Não Existia')" -ForegroundColor Green
    }
    catch {
        Write-Host "Erro ao acelerar Menu Iniciar: $_" -ForegroundColor Red
    }
}

# 4. Tweak: Otimizar Hibernação (Desativar)
function Disable-Hibernation {
    Write-Host "Aplicando Tweak: Desativar Hibernação (libera espaço em disco)..." -ForegroundColor Cyan
    try {
        powercfg /h off | Out-Null
        Write-Host "Hibernação desativada. Para reativar: powercfg /h on" -ForegroundColor Green
    }
    catch {
        Write-Host "Erro ao desativar hibernação: $_" -ForegroundColor Red
    }
}

# 5. Tweak: Ajustes de TCP (Netsh) - Desativar Nagle's Algorithm
function Optimize-TCP {
    Write-Host "Aplicando Tweak: Otimizar TCP (Desativar Nagle's Algorithm)..." -ForegroundColor Cyan
    $keyPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
    
    try {
        # Iterar sobre todas as interfaces de rede
        Get-ChildItem -Path $keyPath | ForEach-Object {
            $interfaceKey = $_.PSPath
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
            Write-Host "  - Interface $($_.Name): TcpNoDelay=1 (Original: $($originalTcpNoDelay -replace '^$', 'Não Existia')), TcpAckFrequency=1 (Original: $($originalTcpAckFrequency -replace '^$', 'Não Existia'))" -ForegroundColor DarkGreen
        }
        Write-Host "Ajustes de TCP aplicados. Pode ser necessário reiniciar para efeito total." -ForegroundColor Green
    }
    catch {
        Write-Host "Erro ao otimizar TCP: $_" -ForegroundColor Red
    }
}

function Invoke-SystemTweaks {
    Write-Host "\n=========================================" -ForegroundColor Yellow
    Write-Host "  Windows Maintenance Suite - Ajustes de Sistema " -ForegroundColor Yellow
    Write-Host "=========================================" -ForegroundColor Yellow
    Write-Host "\nSelecione os ajustes que deseja aplicar:"
    Write-Host "  1. Ativar Plano de Energia 'Desempenho Máximo'"
    Write-Host "  2. Desativar Telemetria Básica"
    Write-Host "  3. Acelerar Resposta do Menu Iniciar"
    Write-Host "  4. Desativar Hibernação (Libera espaço em disco)"
    Write-Host "  5. Otimizar TCP (Desativar Nagle's Algorithm)"
    Write-Host "  6. Aplicar TODOS os ajustes acima"
    Write-Host "  7. Voltar ao Menu Principal"
    Write-Host "\n=========================================" -ForegroundColor Yellow

    $choice = Read-Host "Digite o número da sua escolha"

    switch ($choice) {
        "1" { Set-HighPerformancePowerPlan }
        "2" { Disable-BasicTelemetry }
        "3" { SpeedUp-StartMenu }
        "4" { Disable-Hibernation }
        "5" { Optimize-TCP }
        "6" {
            Set-HighPerformancePowerPlan
            Disable-BasicTelemetry
            SpeedUp-StartMenu
            Disable-Hibernation
            Optimize-TCP
        }
        "7" { return }
        default {
            Write-Host "Opção inválida. Por favor, tente novamente." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
}

Export-ModuleMember -Function Invoke-SystemTweaks, Backup-RegistryKey, Set-HighPerformancePowerPlan, Disable-BasicTelemetry, SpeedUp-StartMenu, Disable-Hibernation, Optimize-TCP
