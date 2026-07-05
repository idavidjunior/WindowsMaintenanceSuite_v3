# Test service toggle mechanisms (read-only + dry-run checks)
$ErrorActionPreference = 'Continue'

function Test-ServiceStartMode {
    param([string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    $cim = Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    if (-not $svc) { Write-Host "$Name : NOT FOUND"; return }
    
    $startType = $null
    if ($svc.PSObject.Properties.Name -contains 'StartType') {
        $startType = [string]$svc.StartType
    }
    Write-Host "$Name : Get-Service StartType=$startType Status=$($svc.Status) | CIM StartMode=$($cim.StartMode) State=$($cim.State)"
}

Write-Host "=== Current state ==="
@('DiagTrack','Fax','Spooler','SysMain','XblAuthManager','WSearch') | ForEach-Object { Test-ServiceStartMode $_ }

Write-Host "`n=== Test Set-Service on Fax (if exists) ==="
$fax = Get-Service Fax -EA SilentlyContinue
if ($fax) {
    $origMode = (Get-CimInstance Win32_Service -Filter "Name='Fax'").StartMode
    Write-Host "Original StartMode: $origMode"
    
    try {
        if ($origMode -ne 'Disabled') {
            if ($fax.Status -eq 'Running') { Stop-Service Fax -Force -EA SilentlyContinue }
            Set-Service -Name Fax -StartupType Disabled -EA Stop
            $after = (Get-CimInstance Win32_Service -Filter "Name='Fax'").StartMode
            Write-Host "After Set-Service Disabled: $after"
            Set-Service -Name Fax -StartupType Manual -EA Stop
            $restored = (Get-CimInstance Win32_Service -Filter "Name='Fax'").StartMode
            Write-Host "After restore Manual: $restored"
        } else {
            Set-Service -Name Fax -StartupType Manual -EA Stop
            $after = (Get-CimInstance Win32_Service -Filter "Name='Fax'").StartMode
            Write-Host "After enable Manual: $after"
            Set-Service -Name Fax -StartupType Disabled -EA Stop
            Write-Host "Restored to Disabled"
        }
    } catch {
        Write-Host "Set-Service FAILED: $($_.Exception.Message)"
        Write-Host "Trying sc.exe fallback..."
        $r = sc.exe config Fax start= demand 2>&1
        Write-Host "sc.exe result: $r"
    }
}

Write-Host "`n=== Test sc.exe config syntax ==="
sc.exe qc DiagTrack 2>&1 | Select-Object -First 5
