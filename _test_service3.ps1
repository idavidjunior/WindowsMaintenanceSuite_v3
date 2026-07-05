$ErrorActionPreference = 'Stop'
. "c:\Users\Playtec-bancada\Desktop\Downloads\WindowsMaintenanceSuite_v3-main-extracted\WindowsMaintenanceSuite_v3-main\WindowsMaintenanceSuite\Core\SecurityHelper.ps1"
. "c:\Users\Playtec-bancada\Desktop\Downloads\WindowsMaintenanceSuite_v3-main-extracted\WindowsMaintenanceSuite_v3-main\WindowsMaintenanceSuite\Core\Logger.ps1"
. "c:\Users\Playtec-bancada\Desktop\Downloads\WindowsMaintenanceSuite_v3-main-extracted\WindowsMaintenanceSuite_v3-main\WindowsMaintenanceSuite\Modules\SystemLightweight.ps1"

Write-Host "=== Helper tests ==="
foreach ($name in @('DiagTrack','Spooler','SysMain')) {
    $mode = Get-ServiceStartModeSafe -ServiceName $name
    $label = Format-ServiceStartModeLabel -StartMode $mode
    $disabled = Test-ServiceIsDisabled -ServiceName $name
    Write-Host "$name -> mode=$mode label=$label disabled=$disabled"
}

$available = Get-AvailableNonEssentialServices -Catalog (Get-NonEssentialServicesCatalog)
Write-Host "`nCatalogados disponiveis: $($available.Count)"
foreach ($a in $available) {
    Write-Host "  $($a.Index). $($a.Info.Name) [$($a.StartMode)]"
}

Write-Host "`nValidacao numerica sel=0:" (Test-ValidNumericInput -Value '0' -Min 1 -Max $available.Count)
Write-Host "Validacao numerica sel=1:" (Test-ValidNumericInput -Value '1' -Min 1 -Max $available.Count)

Write-Host "`nOK - helpers carregados sem erro."
