$here = Split-Path -Parent $PSCommandPath
$coreDir = Join-Path (Split-Path -Parent $here) 'Core'
. (Join-Path $coreDir 'ConfigManager.ps1')
. (Join-Path $coreDir 'Logger.ps1')

Describe 'Write-Log' {
    $logDir = Join-Path $coreDir '..\Logs'
    $today = Get-Date -Format 'yyyy-MM-dd'
    $logFile = Join-Path $logDir "WMS_$today.log"

    It 'creates a log file on INFO level' {
        Write-Log -Message 'Test log message' -Level 'INFO'
        Test-Path $logFile | Should Be $true
    }

    It 'writes message content to log file' {
        $content = Get-Content $logFile -Tail 1
        $content -match 'Test log message' | Should Be $true
    }

    It 'includes level in log entry' {
        $content = Get-Content $logFile -Tail 1
        $content -match '\[INFO\]' | Should Be $true
    }

    It 'accepts WARNING level' {
        Write-Log -Message 'Warning test' -Level 'WARNING'
        $content = Get-Content $logFile -Tail 1
        $content -match '\[WARNING\]' | Should Be $true
    }

    It 'accepts ERROR level' {
        Write-Log -Message 'Error test' -Level 'ERROR'
        $content = Get-Content $logFile -Tail 1
        $content -match '\[ERROR\]' | Should Be $true
    }

    It 'accepts SUCCESS level' {
        Write-Log -Message 'Success test' -Level 'SUCCESS'
        $content = Get-Content $logFile -Tail 1
        $content -match '\[SUCCESS\]' | Should Be $true
    }
}
