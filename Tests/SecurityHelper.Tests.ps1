$here = Split-Path -Parent $PSCommandPath
$coreDir = Join-Path (Split-Path -Parent $here) 'Core'
. (Join-Path $coreDir 'SecurityHelper.ps1')

Describe 'Test-Administrator' {
    It 'returns a boolean' {
        ($result = Test-Administrator) -is [bool] | Should Be $true
    }
}

Describe 'Test-ExternalCommand' {
    It 'returns true for powershell.exe' {
        Test-ExternalCommand -Command 'powershell.exe' | Should Be $true
    }
    It 'returns false for nonexistent command' {
        Test-ExternalCommand -Command 'nonexistentxyz123' | Should Be $false
    }
}

Describe 'Test-ValidNumericInput' {
    It 'validates number within range' {
        Test-ValidNumericInput -Value '5' -Min 1 -Max 10 | Should Be $true
    }
    It 'rejects number below min' {
        Test-ValidNumericInput -Value '0' -Min 1 -Max 10 | Should Be $false
    }
    It 'rejects number above max' {
        Test-ValidNumericInput -Value '11' -Min 1 -Max 10 | Should Be $false
    }
    It 'rejects non-numeric input' {
        Test-ValidNumericInput -Value 'abc' -Min 1 -Max 10 | Should Be $false
    }
    It 'rejects empty input' {
        Test-ValidNumericInput -Value '' -Min 1 -Max 10 | Should Be $false
    }
    It 'handles whitespace' {
        Test-ValidNumericInput -Value ' 3 ' -Min 1 -Max 10 | Should Be $true
    }
}

Describe 'Mask-MacAddress' {
    It 'masks by default' {
        Mask-MacAddress -MacAddress '00:1A:2B:3C:4D:5E' | Should Be '00:1A:XX:XX:XX:XX'
    }
    It 'shows full when ShowFull' {
        Mask-MacAddress -MacAddress '00:1A:2B:3C:4D:5E' -ShowFull $true | Should Be '00:1A:2B:3C:4D:5E'
    }
    It 'handles short input' {
        Mask-MacAddress -MacAddress 'AB' | Should Be 'XX:XX:XX:XX:XX:XX'
    }
}

Describe 'Get-SafeErrorMessage' {
    It 'detects access denied' {
        $result = Get-SafeErrorMessage -Error 'access denied to resource'
        $result -match 'Acesso negado' | Should Be $true
    }
    It 'detects not found' {
        $result = Get-SafeErrorMessage -Error 'file not found'
        $result -match 'encontrado' | Should Be $true
    }
    It 'detects registry error' {
        $result = Get-SafeErrorMessage -Error 'registry key error'
        $result -match 'registro' | Should Be $true
    }
    It 'detects network error' {
        $result = Get-SafeErrorMessage -Error 'network connection lost'
        $result -match 'rede' | Should Be $true
    }
    It 'generic fallback' {
        $result = Get-SafeErrorMessage -Error 'some random error'
        $result -match 'operacional' | Should Be $true
    }
}

Describe 'Convert-PathToSafeFileName' {
    It 'replaces backslashes' {
        Convert-PathToSafeFileName -Path 'HKLM\Software\Test' | Should Be 'HKLM_Software_Test'
    }
    It 'replaces colons with underscores' {
        $result = Convert-PathToSafeFileName -Path 'HKLM:\Software'
        $result -match 'HKLM' | Should Be $true
        $result -match 'Software' | Should Be $true
    }
    It 'trims underscores' {
        Convert-PathToSafeFileName -Path '\Test\' | Should Be 'Test'
    }
}

Describe 'Invoke-WithRollback' {
    It 'executes scriptblock on success' {
        Invoke-WithRollback -ScriptBlock { $true } -RollbackScript { $null } | Should Be $true
    }
    It 'executes rollback on failure (return value is false)' {
        $result = Invoke-WithRollback -ScriptBlock { throw 'fail' } -RollbackScript { $null }
        $result | Should Be $false
    }
}

Describe 'Get-DiskFreeGB' {
    It 'returns positive number' {
        (Get-DiskFreeGB) -gt 0 | Should Be $true
    }
}

Describe 'Get-FolderSizeGB' {
    It 'returns 0 for nonexistent path' {
        Get-FolderSizeGB -Path 'X:\nonexistent_xyz_test' | Should Be 0
    }
    It 'returns number for TEMP' {
        (Get-FolderSizeGB -Path $env:TEMP) -ge 0 | Should Be $true
    }
}

Describe 'Wait-KeyPress' {
    It 'is a defined command' {
        (Get-Command Wait-KeyPress -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
    }
}
