function Invoke-SmartDiagnostics {
    Write-Log "Iniciando Diagnóstico SMART dos Discos..." "INFO"
    
    $Disks = Get-PhysicalDisk
    
    foreach ($disk in $Disks) {
        Write-Host "----------------------------------------------------"
        Write-Host "Disco: $($disk.FriendlyName)" -ForegroundColor Cyan
        Write-Host "Modelo: $($disk.Model)"
        if ($disk.HealthStatus -eq "Healthy") {
            Write-Host "Saúde: $($disk.HealthStatus)" -ForegroundColor Green
        } else {
            Write-Host "Saúde: $($disk.HealthStatus)" -ForegroundColor Red
        }
        Write-Host "Status Operacional: $($disk.OperationalStatus)"
        
        if ($disk.BusType -eq "NVMe" -or $disk.BusType -eq "SSD") {
            # Tentar pegar desgaste se disponível via StorageReliabilityCounter
            $Reliability = Get-StorageReliabilityCounter -PhysicalDisk $disk -ErrorAction SilentlyContinue
            if ($Reliability) {
                Write-Host "Desgaste (Wear): $($Reliability.Wear)%"
                Write-Host "Temperatura: $($Reliability.Temperature)°C"
            }
        }
    }
    
    Update-WMSHistory -Key "LastSmartDiag" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    Write-Log "Diagnóstico SMART concluído." "SUCCESS"
}

