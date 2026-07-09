$here = Split-Path -Parent $PSCommandPath
$coreDir = Join-Path (Split-Path -Parent $here) 'Core'
. (Join-Path $coreDir 'HealthEngine.ps1')

Describe 'Get-SystemHealthScore' {
    It 'returns a score object' {
        $result = Get-SystemHealthScore
        $result | Should Not BeNullOrEmpty
    }
    It 'score is between 0 and 100' {
        $result = Get-SystemHealthScore
        $result.Score -ge 0 | Should Be $true
        $result.Score -le 100 | Should Be $true
    }
    It 'Deductions is an array' {
        $result = Get-SystemHealthScore
        ($result.Deductions -is [array]) | Should Be $true
    }
}
