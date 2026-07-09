<#
.SYNOPSIS
    Módulo para monitoramento de desempenho do sistema.
.DESCRIPTION
    Este módulo fornece métricas detalhadas de desempenho do sistema Windows,
    incluindo CPU, memória, disco, rede e processos.
#>

$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
. "$moduleRoot\..\Core\SecurityHelper.ps1"
. "$moduleRoot\..\Core\ConfigManager.ps1"
. "$moduleRoot\..\Core\Logger.ps1"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$config = Get-WMSConfig
$ShowFullMacAddress = if ($config.ShowFullMacAddress) { $config.ShowFullMacAddress } else { $false }

function Get-PerformanceReport {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  RELATÓRIO DE DESEMPENHO DO SISTEMA" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    Write-Host "`n[1/6] INFORMAÇÕES DE CPU" -ForegroundColor Yellow
    try {
        $cpu = Get-WmiObject Win32_Processor -ErrorAction SilentlyContinue
        $cpuUsage = (Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue).CounterSamples.CookedValue
        $cpuCores = if ($cpu) { $cpu.NumberOfCores } else { 'N/D' }
        $cpuLogicalProcessors = if ($cpu) { $cpu.NumberOfLogicalProcessors } else { 'N/D' }
        $cpuName = if ($cpu) { $cpu.Name } else { 'N/D' }
        $cpuMaxClockSpeed = if ($cpu) { [math]::Round(($cpu.MaxClockSpeed / 1000), 2) } else { 'N/D' }

        Write-Host "      Processador: $cpuName" -ForegroundColor White
        Write-Host "      Núcleos Físicos: $cpuCores" -ForegroundColor White
        Write-Host "      Núcleos Lógicos: $cpuLogicalProcessors" -ForegroundColor White
        Write-Host "      Clock Máximo: $cpuMaxClockSpeed GHz" -ForegroundColor White
        Write-Host "      Uso Atual: $([math]::Round($cpuUsage, 2))%" -ForegroundColor $(if ($cpuUsage -lt 50) { 'Green' } elseif ($cpuUsage -lt 80) { 'Yellow' } else { 'Red' })
    } catch {
        Write-Host "      [ERRO] Não foi possível obter informações da CPU: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
    }

    Write-Host "`n[2/6] INFORMAÇÕES DE MEMÓRIA" -ForegroundColor Yellow
    try {
        $os = Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) {
            $totalMemory = $os.TotalVisibleMemorySize / 1MB
            $freeMemory = $os.FreePhysicalMemory / 1MB
            $usedMemory = $totalMemory - $freeMemory
            $memoryUsage = ($usedMemory / $totalMemory) * 100

            Write-Host "      RAM Total: $([math]::Round($totalMemory, 2)) GB" -ForegroundColor White
            Write-Host "      RAM Usada: $([math]::Round($usedMemory, 2)) GB" -ForegroundColor White
            Write-Host "      RAM Livre: $([math]::Round($freeMemory, 2)) GB" -ForegroundColor White
            Write-Host "      Uso de Memória: $([math]::Round($memoryUsage, 2))%" -ForegroundColor $(if ($memoryUsage -lt 70) { 'Green' } elseif ($memoryUsage -lt 85) { 'Yellow' } else { 'Red' })
        }
    } catch {
        Write-Host "      [ERRO] Não foi possível obter informações de memória: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
    }

    Write-Host "`n[3/6] INFORMAÇÕES DE DISCO" -ForegroundColor Yellow
    try {
        $disks = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $null -ne $_.DriveLetter }
        if ($disks) {
            foreach ($disk in $disks) {
                $diskSize = if ($disk.Size) { $disk.Size / 1GB } else { $null }
                $diskFree = if ($disk.SizeRemaining) { $disk.SizeRemaining / 1GB } else { $null }
                if ($diskSize -and $diskFree) {
                    $diskUsed = $diskSize - $diskFree
                    $diskUsage = ($diskUsed / $diskSize) * 100

                    Write-Host "      Drive $($disk.DriveLetter):" -ForegroundColor White
                    Write-Host "        Tamanho Total: $([math]::Round($diskSize, 2)) GB" -ForegroundColor White
                    Write-Host "        Espaço Usado: $([math]::Round($diskUsed, 2)) GB" -ForegroundColor White
                    Write-Host "        Espaço Livre: $([math]::Round($diskFree, 2)) GB" -ForegroundColor White
                    Write-Host "        Uso: $([math]::Round($diskUsage, 2))%" -ForegroundColor $(if ($diskUsage -lt 80) { 'Green' } elseif ($diskUsage -lt 90) { 'Yellow' } else { 'Red' })
                    Write-Host "        Sistema de Arquivos: $($disk.FileSystem)" -ForegroundColor White
                } else {
                    Write-Host "      Drive $($disk.DriveLetter): informações indisponíveis" -ForegroundColor Yellow
                }
            }
        } else {
            Write-Host "      [INFO] Nenhum volume local disponível para análise." -ForegroundColor Cyan
        }
    } catch {
        Write-Host "      [ERRO] Não foi possível obter informações de disco: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
    }

    Write-Host "`n[4/6] INFORMAÇÕES DE REDE" -ForegroundColor Yellow
    try {
        $networkAdapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
        foreach ($adapter in $networkAdapters) {
            Write-Host "      Adaptador: $($adapter.Name)" -ForegroundColor White
            Write-Host "        Status: $($adapter.Status)" -ForegroundColor Green
            Write-Host "        Link Speed: $($adapter.LinkSpeed)" -ForegroundColor White
            $maskedMac = Mask-MacAddress -MacAddress $adapter.MacAddress -ShowFull $ShowFullMacAddress
            Write-Host "        MAC Address: $maskedMac" -ForegroundColor White
        }
    } catch {
        Write-Host "      [ERRO] Não foi possível obter informações de rede: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
    }

    Write-Host "`n[5/6] TOP 5 PROCESSOS" -ForegroundColor Yellow
    try {
        $topCpuProcesses = Get-Process | Sort-Object CPU -Descending | Select-Object -First 5
        foreach ($process in $topCpuProcesses) {
            $cpuTime = if ($process.CPU) { [math]::Round($process.CPU.TotalSeconds, 2) } else { 0 }
            Write-Host "      $($process.ProcessName.PadRight(20)) - CPU: ${cpuTime}s" -ForegroundColor White
        }
    } catch {
        Write-Host "      [ERRO] Não foi possível obter informações de processos: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
    }

    Write-Host "`n[6/6] INFORMAÇÕES ADICIONAIS" -ForegroundColor Yellow
    try {
        $uptime = (Get-Date) - (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).LastBootUpTime
        if ($uptime) {
            $uptimeDays = [math]::Floor($uptime.TotalDays)
            $uptimeHours = [math]::Floor($uptime.Hours)
            $uptimeMinutes = [math]::Floor($uptime.Minutes)
            Write-Host "      Tempo de Atividade: ${uptimeDays}d ${uptimeHours}h ${uptimeMinutes}m" -ForegroundColor White
        }

        $criticalServices = @('Winmgmt', 'RpcSs', 'EventLog', 'Schedule')
        foreach ($serviceName in $criticalServices) {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($service) {
                $statusColor = if ($service.Status -eq 'Running') { 'Green' } else { 'Red' }
                Write-Host "        $serviceName : $($service.Status)" -ForegroundColor $statusColor
            }
        }
    } catch {
        Write-Host "      [ERRO] Não foi possível obter informações adicionais: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
    }

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  FIM DO RELATÓRIO" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    Write-Log "Relatório de desempenho gerado com sucesso" 'INFO'
}

function Invoke-PerformanceMonitor {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  MONITOR DE DESEMPENHO" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "`nSelecione uma opção:" -ForegroundColor Cyan
    Write-Host "  1. Gerar relatório completo de desempenho"
    Write-Host "  2. Monitoramento contínuo (atualiza a cada 5 segundos)"
    Write-Host "  3. Voltar ao Menu Principal"
    Write-Host "`n========================================" -ForegroundColor Cyan

    $choice = Read-Host 'Digite o número da sua escolha'
    $choice = $choice -replace '\s+', ''

    if (-not (Test-ValidNumericInput -Value $choice -Min 1 -Max 3)) {
        Write-Host 'Opção inválida. Por favor, digite um número entre 1 e 3.' -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }

    switch ($choice) {
        '1' {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Get-PerformanceReport
            Write-Host "`nPressione qualquer tecla para continuar..."
            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            Write-Host "========================================" -ForegroundColor Cyan
        }
        '2' {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Write-Host "  MONITORAMENTO CONTÍNUO" -ForegroundColor Cyan
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host "`nPressione 'Q' para parar o monitoramento..."

            while ($true) {
                Clear-Host
                Write-Host "========================================" -ForegroundColor Cyan
                Write-Host "  MONITORAMENTO CONTÍNUO (Pressione Q para sair)" -ForegroundColor Cyan
                Write-Host "========================================" -ForegroundColor Cyan
                Write-Host "Última atualização: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Cyan

                try {
                    $cpuUsage = (Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue).CounterSamples.CookedValue
                    $os = Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue
                    $totalMemory = if ($os) { $os.TotalVisibleMemorySize / 1MB } else { $null }
                    $freeMemory = if ($os) { $os.FreePhysicalMemory / 1MB } else { $null }
                    $memoryUsage = if ($totalMemory -and $freeMemory) { ((($totalMemory - $freeMemory) / $totalMemory) * 100) } else { $null }

                    Write-Host "CPU: $([math]::Round($cpuUsage, 1))%" -ForegroundColor $(if ($cpuUsage -lt 50) { 'Green' } elseif ($cpuUsage -lt 80) { 'Yellow' } else { 'Red' })
                    if ($memoryUsage -ne $null) {
                        Write-Host "RAM: $([math]::Round($memoryUsage, 1))%" -ForegroundColor $(if ($memoryUsage -lt 70) { 'Green' } elseif ($memoryUsage -lt 85) { 'Yellow' } else { 'Red' })
                    }
                } catch {
                    Write-Host "[ERRO] Não foi possível atualizar o monitor: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
                }

                Start-Sleep -Seconds 5
                if ($Host.UI.RawUI.KeyAvailable) {
                    $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
                    if ($key.Character -eq 'q' -or $key.Character -eq 'Q') {
                        break
                    }
                }
            }

            Write-Host "`nMonitoramento interrompido." -ForegroundColor Yellow
        }
        '3' { return }
    }
}


