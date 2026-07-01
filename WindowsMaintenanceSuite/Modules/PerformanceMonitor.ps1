<#
.SYNOPSIS
    Módulo para monitoramento de desempenho do sistema.
.DESCRIPTION
    Este módulo fornece métricas detalhadas de desempenho do sistema Windows,
    incluindo CPU, memória, disco, rede e processos.
#>

# Importar SecurityHelper
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\SecurityHelper.ps1"

# Importar ConfigManager para obter configurações
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\ConfigManager.ps1"
$config = Get-WMSConfig
$ShowFullMacAddress = if ($config.ShowFullMacAddress) { $config.ShowFullMacAddress } else { $false }

function Get-PerformanceReport {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  RELATÓRIO DE DESEMPENHO DO SISTEMA" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    # 1. Informações de CPU
    Write-Host "`n[1/6] INFORMAÇÕES DE CPU" -ForegroundColor Yellow
    try {
        $cpu = Get-WmiObject Win32_Processor
        $cpuUsage = (Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue).CounterSamples.CookedValue
        $cpuCores = $cpu.NumberOfCores
        $cpuLogicalProcessors = $cpu.NumberOfLogicalProcessors
        $cpuName = $cpu.Name
        $cpuMaxClockSpeed = $cpu.MaxClockSpeed / 1000  # Convert to GHz

        Write-Host "      Processador: $cpuName" -ForegroundColor White
        Write-Host "      Núcleos Físicos: $cpuCores" -ForegroundColor White
        Write-Host "      Núcleos Lógicos: $cpuLogicalProcessors" -ForegroundColor White
        Write-Host "      Clock Máximo: $cpuMaxClockSpeed GHz" -ForegroundColor White
        Write-Host "      Uso Atual: $([math]::Round($cpuUsage, 2))%" -ForegroundColor $(if ($cpuUsage -lt 50) { "Green" } elseif ($cpuUsage -lt 80) { "Yellow" } else { "Red" })

        # Utilização por núcleo
        Write-Host "`n      Utilização por Núcleo:" -ForegroundColor Cyan
        $coreCount = 0
        Get-Counter '\Processor(*)\% Processor Time' -ErrorAction SilentlyContinue | ForEach-Object {
            $_.CounterSamples | Where-Object { $_.InstanceName -match '^\d+,' } | ForEach-Object {
                if ($coreCount -lt $cpuLogicalProcessors) {
                    $coreUsage = [math]::Round($_.CookedValue, 1)
                    $color = if ($coreUsage -lt 50) { "Green" } elseif ($coreUsage -lt 80) { "Yellow" } else { "Red" }
                    Write-Host "      Núcleo $coreCount : $coreUsage%" -ForegroundColor $color
                    $coreCount++
                }
            }
        }
    } catch {
        Write-Host "      [ERRO] Não foi possível obter informações da CPU: $_" -ForegroundColor Red
    }

    # 2. Informações de Memória
    Write-Host "`n[2/6] INFORMAÇÕES DE MEMÓRIA" -ForegroundColor Yellow
    try {
        $os = Get-WmiObject Win32_OperatingSystem
        $totalMemory = $os.TotalVisibleMemorySize / 1MB  # Convert to GB
        $freeMemory = $os.FreePhysicalMemory / 1MB  # Convert to GB
        $usedMemory = $totalMemory - $freeMemory
        $memoryUsage = ($usedMemory / $totalMemory) * 100

        Write-Host "      RAM Total: $([math]::Round($totalMemory, 2)) GB" -ForegroundColor White
        Write-Host "      RAM Usada: $([math]::Round($usedMemory, 2)) GB" -ForegroundColor White
        Write-Host "      RAM Livre: $([math]::Round($freeMemory, 2)) GB" -ForegroundColor White
        Write-Host "      Uso de Memória: $([math]::Round($memoryUsage, 2))%" -ForegroundColor $(if ($memoryUsage -lt 70) { "Green" } elseif ($memoryUsage -lt 85) { "Yellow" } else { "Red" })

        # Memória virtual
        $pageFile = Get-WmiObject Win32_PageFileUsage
        if ($pageFile) {
            $pageFileUsage = ($pageFile.CurrentUsage / $pageFile.AllocatedBaseSize) * 100
            Write-Host "      Uso de Page File: $([math]::Round($pageFileUsage, 2))%" -ForegroundColor $(if ($pageFileUsage -lt 50) { "Green" } elseif ($pageFileUsage -lt 75) { "Yellow" } else { "Red" })
        }
    } catch {
        Write-Host "      [ERRO] Não foi possível obter informações de memória: $_" -ForegroundColor Red
    }

    # 3. Informações de Disco
    Write-Host "`n[3/6] INFORMAÇÕES DE DISCO" -ForegroundColor Yellow
    try {
        $disks = Get-Volume | Where-Object { $null -ne $_.DriveLetter }
        foreach ($disk in $disks) {
            $diskSize = $disk.Size / 1GB
            $diskFree = $disk.SizeRemaining / 1GB
            $diskUsed = $diskSize - $diskFree
            $diskUsage = ($diskUsed / $diskSize) * 100

            Write-Host "      Drive $($disk.DriveLetter):" -ForegroundColor White
            Write-Host "        Tamanho Total: $([math]::Round($diskSize, 2)) GB" -ForegroundColor White
            Write-Host "        Espaço Usado: $([math]::Round($diskUsed, 2)) GB" -ForegroundColor White
            Write-Host "        Espaço Livre: $([math]::Round($diskFree, 2)) GB" -ForegroundColor White
            Write-Host "        Uso: $([math]::Round($diskUsage, 2))%" -ForegroundColor $(if ($diskUsage -lt 80) { "Green" } elseif ($diskUsage -lt 90) { "Yellow" } else { "Red" })
            Write-Host "        Sistema de Arquivos: $($disk.FileSystem)" -ForegroundColor White
        }

        # I/O de disco
        Write-Host "`n      I/O de Disco (últimos 5 segundos):" -ForegroundColor Cyan
        $diskIO = Get-Counter '\PhysicalDisk(_Total)\Disk Read Bytes/sec','\PhysicalDisk(_Total)\Disk Write Bytes/sec' -ErrorAction SilentlyContinue
        if ($diskIO) {
            $readBytes = $diskIO.CounterSamples[0].CookedValue / 1MB  # Convert to MB/s
            $writeBytes = $diskIO.CounterSamples[1].CookedValue / 1MB  # Convert to MB/s
            Write-Host "        Leitura: $([math]::Round($readBytes, 2)) MB/s" -ForegroundColor Green
            Write-Host "        Escrita: $([math]::Round($writeBytes, 2)) MB/s" -ForegroundColor Green
        }
    } catch {
        Write-Host "      [ERRO] Não foi possível obter informações de disco: $_" -ForegroundColor Red
    }

    # 4. Informações de Rede
    Write-Host "`n[4/6] INFORMAÇÕES DE REDE" -ForegroundColor Yellow
    try {
        $networkAdapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
        foreach ($adapter in $networkAdapters) {
            Write-Host "      Adaptador: $($adapter.Name)" -ForegroundColor White
            Write-Host "        Status: $($adapter.Status)" -ForegroundColor Green
            Write-Host "        Link Speed: $($adapter.LinkSpeed)" -ForegroundColor White
            $maskedMac = Mask-MacAddress -MacAddress $adapter.MacAddress -ShowFull $ShowFullMacAddress
            Write-Host "        MAC Address: $maskedMac" -ForegroundColor White

            # Estatísticas de interface
            $stats = Get-NetAdapterStatistics -Name $adapter.Name -ErrorAction SilentlyContinue
            if ($stats) {
                $receivedMB = $stats.ReceivedBytes / 1MB
                $sentMB = $stats.SentBytes / 1MB
                Write-Host "        Recebido: $([math]::Round($receivedMB, 2)) MB" -ForegroundColor Green
                Write-Host "        Enviado: $([math]::Round($sentMB, 2)) MB" -ForegroundColor Green
            }
        }

        # Tráfego de rede atual
        Write-Host "`n      Tráfego de Rede Atual:" -ForegroundColor Cyan
        $networkTraffic = Get-Counter '\Network Interface(*)\Bytes Total/sec' -ErrorAction SilentlyContinue
        if ($networkTraffic) {
            $networkTraffic.CounterSamples | Where-Object { $_.InstanceName -notmatch '_Total' } | ForEach-Object {
                $trafficMB = $_.CookedValue / 1MB
                if ($trafficMB -gt 0.01) {
                    Write-Host "        $($_.InstanceName): $([math]::Round($trafficMB, 2)) MB/s" -ForegroundColor Green
                }
            }
        }
    } catch {
        Write-Host "      [ERRO] Não foi possível obter informações de rede: $_" -ForegroundColor Red
    }

    # 5. Top Processos por Recursos
    Write-Host "`n[5/6] TOP 5 PROCESSOS POR USO DE CPU" -ForegroundColor Yellow
    try {
        $topCpuProcesses = Get-Process | Sort-Object CPU -Descending | Select-Object -First 5
        foreach ($process in $topCpuProcesses) {
            $cpuTime = if ($process.CPU) { [math]::Round($process.CPU.TotalSeconds, 2) } else { 0 }
            Write-Host "      $($process.ProcessName.PadRight(20)) - CPU: ${cpuTime}s" -ForegroundColor White
        }
    } catch {
        Write-Host "      [ERRO] Não foi possível obter informações de processos: $_" -ForegroundColor Red
    }

    Write-Host "`n      TOP 5 PROCESSOS POR USO DE MEMÓRIA" -ForegroundColor Yellow
    try {
        $topMemoryProcesses = Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First 5
        foreach ($process in $topMemoryProcesses) {
            $memoryMB = $process.WorkingSet / 1MB
            Write-Host "      $($process.ProcessName.PadRight(20)) - RAM: $([math]::Round($memoryMB, 2)) MB" -ForegroundColor White
        }
    } catch {
        Write-Host "      [ERRO] Não foi possível obter informações de processos: $_" -ForegroundColor Red
    }

    # 6. Informações Adicionais
    Write-Host "`n[6/6] INFORMAÇÕES ADICIONAIS" -ForegroundColor Yellow
    try {
        # Tempo de atividade
        $uptime = (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        $uptimeDays = [math]::Floor($uptime.TotalDays)
        $uptimeHours = [math]::Floor($uptime.Hours)
        $uptimeMinutes = [math]::Floor($uptime.Minutes)
        Write-Host "      Tempo de Atividade: ${uptimeDays}d ${uptimeHours}h ${uptimeMinutes}m" -ForegroundColor White

        # Temperatura (se disponível)
        Write-Host "`n      Temperaturas (se disponível):" -ForegroundColor Cyan
        $temps = Get-WmiObject MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue
        if ($temps) {
            foreach ($temp in $temps) {
                $tempCelsius = ($temp.CurrentTemperature / 10) - 273.15
                Write-Host "        $($temp.InstanceName): $([math]::Round($tempCelsius, 1))°C" -ForegroundColor $(if ($tempCelsius -lt 60) { "Green" } elseif ($tempCelsius -lt 75) { "Yellow" } else { "Red" })
            }
        } else {
            Write-Host "        [INFO] Sensores de temperatura não disponíveis" -ForegroundColor Cyan
        }

        # Serviços críticos
        Write-Host "`n      Status de Serviços Críticos:" -ForegroundColor Cyan
        $criticalServices = @("Winmgmt", "RpcSs", "EventLog", "Schedule")
        foreach ($serviceName in $criticalServices) {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($service) {
                $statusColor = if ($service.Status -eq "Running") { "Green" } else { "Red" }
                Write-Host "        $serviceName : $($service.Status)" -ForegroundColor $statusColor
            }
        }
    } catch {
        Write-Host "      [ERRO] Não foi possível obter informações adicionais: $_" -ForegroundColor Red
    }

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  FIM DO RELATÓRIO" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    Write-Log "Relatório de desempenho gerado com sucesso" "INFO"
}

function Invoke-PerformanceMonitor {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  MONITOR DE DESEMPENHO" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "`nSelecione uma opção:"
    Write-Host "  1. Gerar relatório completo de desempenho"
    Write-Host "  2. Monitoramento contínuo (atualiza a cada 5 segundos)"
    Write-Host "  3. Voltar ao Menu Principal"
    Write-Host "`n========================================" -ForegroundColor Cyan

    $choice = Read-Host "Digite o número da sua escolha"

    # Remover espaços em branco
    $choice = $choice -replace '\s+', ''

    # Validar input
    if (-not (Test-ValidNumericInput -Input $choice -Min 1 -Max 3)) {
        Write-Host "Opção inválida. Por favor, digite um número entre 1 e 3." -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }

    switch ($choice) {
        "1" {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Get-PerformanceReport
            Write-Host "`nPressione qualquer tecla para continuar..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            Write-Host "========================================" -ForegroundColor Cyan
        }
        "2" {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Write-Host "  MONITORAMENTO CONTÍNUO" -ForegroundColor Cyan
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host "`nPressione 'Q' para parar o monitoramento..."
            Write-Host ""

            while ($true) {
                Clear-Host
                Write-Host "========================================" -ForegroundColor Cyan
                Write-Host "  MONITORAMENTO CONTÍNUO (Pressione Q para sair)" -ForegroundColor Cyan
                Write-Host "========================================" -ForegroundColor Cyan
                Write-Host "Última atualização: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Cyan

                # CPU e Memória resumidos
                try {
                    $cpuUsage = (Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue).CounterSamples.CookedValue
                    $os = Get-WmiObject Win32_OperatingSystem
                    $totalMemory = $os.TotalVisibleMemorySize / 1MB
                    $freeMemory = $os.FreePhysicalMemory / 1MB
                    $memoryUsage = (($totalMemory - $freeMemory) / $totalMemory) * 100

                    Write-Host "`nCPU: $([math]::Round($cpuUsage, 1))%" -ForegroundColor $(if ($cpuUsage -lt 50) { "Green" } elseif ($cpuUsage -lt 80) { "Yellow" } else { "Red" })
                    Write-Host "RAM: $([math]::Round($memoryUsage, 1))%" -ForegroundColor $(if ($memoryUsage -lt 70) { "Green" } elseif ($memoryUsage -lt 85) { "Yellow" } else { "Red" })

                    # Top processo
                    $topProcess = Get-Process | Sort-Object CPU -Descending | Select-Object -First 1
                    Write-Host "Top Processo: $($topProcess.ProcessName)" -ForegroundColor White
                } catch {
                    Write-Host "Erro ao obter métricas: $_" -ForegroundColor Red
                }

                # Verificar tecla Q
                if ($Host.UI.RawUI.KeyAvailable) {
                    $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                    if ($key.Character -eq 'q' -or $key.Character -eq 'Q') {
                        break
                    }
                }

                Start-Sleep -Seconds 5
            }

            Write-Host "`nMonitoramento interrompido." -ForegroundColor Yellow
        }
        "3" { return }
        default {
            Write-Host "Opção inválida. Por favor, tente novamente." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
}
