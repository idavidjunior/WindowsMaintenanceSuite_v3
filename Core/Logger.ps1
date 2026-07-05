function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )

    # Importar ConfigManager para obter configurações
    . "$PSScriptRoot\ConfigManager.ps1"
    $config = Get-WMSConfig
    $retentionDays = if ($config.LogRetentionDays) { $config.LogRetentionDays } else { 7 }

    $LogDir = Join-Path $PSScriptRoot "..\Logs"
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

    # Rotacionar logs antigos
    try {
        $logFiles = Get-ChildItem -Path $LogDir -Filter "WMS_*.log" -ErrorAction SilentlyContinue
        $cutoffDate = (Get-Date).AddDays(-$retentionDays)
        foreach ($file in $logFiles) {
            if ($file.LastWriteTime -lt $cutoffDate) {
                Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {
        # Silencioso - não interromper logging se rotação falhar
    }

    $LogFile = Join-Path $LogDir "WMS_$(Get-Date -Format 'yyyy-MM-dd').log"
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Level] $Message"

    Add-Content -Path $LogFile -Value $LogEntry -Encoding UTF8

    # Cores para o console
    switch ($Level) {
        "INFO"    { Write-Host $LogEntry -ForegroundColor Cyan }
        "WARNING" { Write-Host $LogEntry -ForegroundColor Yellow }
        "ERROR"   { Write-Host $LogEntry -ForegroundColor Red }
        "SUCCESS" { Write-Host $LogEntry -ForegroundColor Green }
        default   { Write-Host $LogEntry }
    }
}

