function Get-SystemHealthScore {
    # Inicializa variáveis
    $Score = 100
    $Deductions = @()

    # 1. SMART Health (30%)
    try {
        $SmartStatus = Get-PhysicalDisk | Select-Object -ExpandProperty HealthStatus
        if ($SmartStatus -contains "Warning") { $Score -= 15; $Deductions += "Problemas detectados no SMART (Aviso)" }
        if ($SmartStatus -contains "Unhealthy") { $Score -= 30; $Deductions += "Problemas críticos no SMART" }
    } catch {
        $Score -= 5
    }

    # 2. Windows Integrity (20%) - Baseado no histórico ou verificação rápida
    # (Simulação simplificada para o menu inicial)
    
    # 3. Storage Availability (15%)
    $Disks = Get-Volume | Where-Object { $_.DriveLetter -ne $null }
    foreach ($Disk in $Disks) {
        $FreePercent = ($Disk.SizeRemaining / $Disk.Size) * 100
        if ($FreePercent -lt 10) { $Score -= 5; $Deductions += "Pouco espaço no disco $($Disk.DriveLetter)" }
    }

    # 4. Event Logs (15%)
    $Errors = Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=(Get-Date).AddDays(-1)} -ErrorAction SilentlyContinue
    if ($Errors.Count -gt 50) { $Score -= 10; $Deductions += "Muitos erros de sistema nas últimas 24h" }

    # Garante que o score não seja menor que 0
    if ($Score -lt 0) { $Score = 0 }

    return [PSCustomObject]@{
        Score = $Score
        Deductions = $Deductions
    }
}

Export-ModuleMember -Function Get-SystemHealthScore
