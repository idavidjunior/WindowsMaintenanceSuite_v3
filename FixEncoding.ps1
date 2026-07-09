$p = 'C:\Users\Playtec-bancada\Desktop\Downloads\WindowsMaintenanceSuite_v3-main\WindowsMaintenanceSuite_v3-main\Modules\RegistryScanner.ps1'
$c = Get-Content -Raw -Path $p -Encoding UTF8
Set-Content -Path $p -Value $c -Encoding UTF8
Write-Host 'rewritten with BOM'