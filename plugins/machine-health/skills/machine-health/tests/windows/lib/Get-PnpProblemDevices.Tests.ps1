#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:SkillRoot = Split-Path -Parent $script:TestsRoot
    $script:LibPath = Join-Path $script:SkillRoot 'scripts\windows\lib\Get-PnpProblemDevices.ps1'
    . $script:LibPath
}

Describe 'Get-PnpProblemDevice' -Tag 'lib' {
    AfterEach {
        # Cleanup the script-scope pnputil stub that individual tests install.
        # AfterEach runs even when an assertion failed earlier in the test, so
        # the stub never leaks into subsequent tests.
        Remove-Item function:\pnputil -ErrorAction SilentlyContinue
    }

    It 'returns empty array when pnputil is not on PATH' {
        Mock Get-Command {
            param($Name) if ($Name -eq 'pnputil') { $null }
        }
        $result = @(Get-PnpProblemDevice)
        $result.Count | Should -Be 0
    }

    It 'ignores pnputil preamble banner when no devices have problems (regression)' {
        # Shadow pnputil as a function so the native-command call resolves to
        # our stub. The call operator dispatches to a function of the same
        # name if one is defined in scope.
        function script:pnputil {
            @'
Microsoft PnP Utility

No devices match the specified filter.
'@
        }
        Mock Get-Command { [pscustomobject]@{ Name = 'pnputil' } } -ParameterFilter { $Name -eq 'pnputil' }
        $result = @(Get-PnpProblemDevice)
        $result.Count | Should -Be 0
    }

    It 'parses real device blocks and skips the preamble' {
        function script:pnputil {
            @'
Microsoft PnP Utility

Instance ID: ACPI\MOCK\0000
Device Description: Mock Device
Class Name: Display
Problem Code: 10 (CM_PROB_FAILED_START)
Problem Status: 0xC0000001
'@
        }
        Mock Get-Command { [pscustomobject]@{ Name = 'pnputil' } } -ParameterFilter { $Name -eq 'pnputil' }
        $result = @(Get-PnpProblemDevice)
        $result.Count | Should -Be 1
        $result[0].instance_id | Should -Be 'ACPI\MOCK\0000'
        $result[0].problem_code | Should -Be 10
    }
}
