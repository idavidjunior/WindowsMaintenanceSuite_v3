param([int]$Option, [switch]$KeepOpen)

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$candidates = @(
    (Resolve-Path "$scriptRoot\.." -ErrorAction SilentlyContinue),
    (Resolve-Path "$scriptRoot\..\app" -ErrorAction SilentlyContinue),
    (Resolve-Path "$scriptRoot\..\.." -ErrorAction SilentlyContinue)
)
$projectRoot = $null
foreach ($c in $candidates) {
    if ($c -and (Test-Path (Join-Path $c "Core\Logger.ps1"))) { $projectRoot = $c; break }
}
if (-not $projectRoot) { $projectRoot = Resolve-Path "$scriptRoot\.." }

$corePath = Join-Path $projectRoot "Core"
$modPath = Join-Path $projectRoot "Modules"

@('Logger.ps1','ConfigManager.ps1','HealthEngine.ps1','SecurityHelper.ps1','Scheduler.ps1') | ForEach-Object {
    Import-Module (Join-Path $corePath $_) -Force -DisableNameChecking
}

$modules = @(
    'EssentialMaintenance.ps1','UltimateMaintenance.ps1','DeepDiagnostics.ps1','SmartDiagnostics.ps1',
    'RegistryBackupRestore.ps1','SystemTweaks.ps1','PerformanceMonitor.ps1','DeepCleaning.ps1',
    'SystemLightweight.ps1','DriverManager.ps1','SecurityScan.ps1','RegistryScanner.ps1',
    'QuickTools.ps1','SelfUpdate.ps1','PackageManager.ps1','Profiles.ps1','Hardening.ps1',
    'DiskSpaceAnalyzer.ps1'
)
foreach ($mod in $modules) {
    Import-Module (Join-Path $modPath $mod) -Force -DisableNameChecking
}

if ($KeepOpen) {
    do {
        try {
            switch ($Option) {
                1 { Invoke-EssentialMaintenance }
                2 { Invoke-UltimateMaintenance }
                3 { Invoke-DeepCleaning }
                4 { Invoke-SystemLightweight }
                5 { Invoke-DeepDiagnostics }
                6 { Invoke-SmartDiagnostics }
                7 { Invoke-PerformanceMonitor }
                8 { Invoke-DriverManager }
                9 { Invoke-SystemTweaks }
                10 { Backup-Registry }
                11 {
                    $backupPath = Get-SafeBackupPath
                    if (Test-Path $backupPath) {
                        $latest = Get-ChildItem -Path $backupPath -Filter "RegistryBackup_*.reg" -ErrorAction SilentlyContinue |
                            Sort-Object LastWriteTime -Descending | Select-Object -First 1
                        if ($latest) { Restore-Registry -BackupFile $latest.FullName }
                    }
                }
                12 { Invoke-MaintenanceScheduler }
                13 { Invoke-SecurityScan }
                14 { Invoke-RegistryScan }
                15 { Invoke-QuickToolsMenu }
                16 { Invoke-DiskSpaceAnalyzer }
                17 { Update-WMS }
                18 { Invoke-PackageManagerMenu }
                19 { Invoke-ProfileMenu }
                20 { Invoke-HardeningMenu }
                21 { Invoke-MemoryManager }
            }
            Write-Host "[WMS-OK] Opção $Option concluída."
        } catch {
            Write-Host "[WMS-ERRO] $($_.Exception.Message)"
        }

        do {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Write-Host "  Tarefa concluída!" -ForegroundColor Cyan
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host "  Deseja sair ou continuar?"
            Write-Host "  1. Continuar (voltar ao menu)"
            Write-Host "  2. Sair (fechar e voltar para a interface gráfica)"
            Write-Host "========================================" -ForegroundColor Cyan
            $keepChoice = Read-Host "Digite sua escolha"
            $keepChoice = $keepChoice -replace '\s+', ''
            if ($keepChoice -eq '1') { break }
            if ($keepChoice -eq '2') { return }
            Write-Host "Opção inválida. Digite 1 ou 2." -ForegroundColor Red
        } while ($true)
    } while ($true)
}
