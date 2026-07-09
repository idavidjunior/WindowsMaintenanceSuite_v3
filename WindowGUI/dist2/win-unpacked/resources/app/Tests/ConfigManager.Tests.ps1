$here = Split-Path -Parent $PSCommandPath
$coreDir = Join-Path (Split-Path -Parent $here) 'Core'
. (Join-Path $coreDir 'ConfigManager.ps1')
. (Join-Path $coreDir 'Logger.ps1')

$testConfigPath = Join-Path $coreDir '..\Config\Settings.json'
$testHistoryPath = Join-Path $coreDir '..\History\MaintenanceHistory.json'

Describe 'Get-WMSConfig' {
    It 'returns a config object' {
        $config = Get-WMSConfig
        $config | Should Not BeNullOrEmpty
    }
    It 'has Theme property' {
        $config = Get-WMSConfig
        $config.Theme | Should Be 'Dark'
    }
    It 'has Language property' {
        $config = Get-WMSConfig
        $config.Language | Should Be 'PT-BR'
    }
    It 'has LogRetentionDays property' {
        $config = Get-WMSConfig
        $config.LogRetentionDays | Should Be 7
    }
}

Describe 'Get-WMSHistory' {
    It 'returns a history object' {
        $history = Get-WMSHistory
        $history | Should Not BeNullOrEmpty
    }
    It 'has LastEssential property' {
        $history = Get-WMSHistory
        $history.LastEssential | Should Not BeNullOrEmpty
    }
}

Describe 'Update-WMSHistory' {
    It 'updates a key value' {
        Update-WMSHistory -Key 'TestKey' -Value 'test_value'
        $history = Get-WMSHistory
        $history.TestKey | Should Be 'test_value'
    }
}
