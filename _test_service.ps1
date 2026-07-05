Write-Host "PSVersion:" $PSVersionTable.PSVersion
$s = Get-Service -Name DiagTrack -ErrorAction SilentlyContinue
if ($s) {
    Write-Host "Get-Service properties:" ($s.PSObject.Properties.Name -join ', ')
    Write-Host "StartType property exists:" ($s.PSObject.Properties.Name -contains 'StartType')
    if ($s.PSObject.Properties.Name -contains 'StartType') {
        Write-Host "StartType:" $s.StartType
    }
    Write-Host "Status:" $s.Status
}
$w = Get-CimInstance Win32_Service -Filter "Name='DiagTrack'" -ErrorAction SilentlyContinue
if ($w) {
    Write-Host "CIM StartMode:" $w.StartMode "State:" $w.State
}

# Test string comparison bug
$sel = "1"
Write-Host "sel -ge 1:" ($sel -ge 1)
Write-Host "sel -le 5:" ($sel -le 5)
Write-Host "match and range:" ($sel -match '^\d+$' -and $sel -ge 1 -and $sel -le 5)
