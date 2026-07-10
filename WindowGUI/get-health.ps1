$cpu = [math]::Round((Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average, 0)
$os = Get-CimInstance Win32_OperatingSystem
$ramTotal = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
$ramFree  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
$ramUsed  = $ramTotal - $ramFree
$ramPct   = if ($ramTotal -gt 0) { [math]::Round(($ramUsed / $ramTotal) * 100, 0) } else { 0 }
$disk = Get-PSDrive C -ErrorAction SilentlyContinue
if ($disk -and $disk.Used -gt 0) {
    $dTotal = [math]::Round(($disk.Used + $disk.Free) / 1GB, 0)
    $dFree  = [math]::Round($disk.Free / 1GB, 1)
    $dPct   = [math]::Round(($disk.Used / ($disk.Used + $disk.Free)) * 100, 0)
} else { $dTotal = 0; $dFree = 0; $dPct = 0 }
$uptime = (Get-Date) - $os.LastBootUpTime
$uHours = [math]::Round($uptime.TotalHours, 1)
$score = 100
if ($cpu -gt 80) { $score -= 15 } elseif ($cpu -gt 60) { $score -= 8 }
if ($ramPct -gt 90) { $score -= 15 } elseif ($ramPct -gt 75) { $score -= 5 }
if ($dPct -gt 95) { $score -= 15 } elseif ($dPct -gt 85) { $score -= 5 }
if ($uptime.TotalDays -gt 30) { $score -= 10 } elseif ($uptime.TotalDays -gt 14) { $score -= 5 }
if ($score -lt 0) { $score = 0 }
@{
    cpu=[int]$cpu; ramPct=[int]$ramPct; ramUsed=[int]$ramUsed; ramTotal=[int]$ramTotal
    diskPct=[int]$dPct; diskFree=$dFree; diskTotal=[int]$dTotal; uptimeHours=$uHours; score=[int]$score
} | ConvertTo-Json
