function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )

    $LogDir = Join-Path $PSScriptRoot "..\Logs"
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
    
    $LogFile = Join-Path $LogDir "WMS_$(Get-Date -Format 'yyyy-MM-dd').log"
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Level] $Message"
    
    Add-Content -Path $LogFile -Value $LogEntry
    
    # Cores para o console
    switch ($Level) {
        "INFO"    { Write-Host $LogEntry -ForegroundColor Cyan }
        "WARNING" { Write-Host $LogEntry -ForegroundColor Yellow }
        "ERROR"   { Write-Host $LogEntry -ForegroundColor Red }
        "SUCCESS" { Write-Host $LogEntry -ForegroundColor Green }
        default   { Write-Host $LogEntry }
    }
}

