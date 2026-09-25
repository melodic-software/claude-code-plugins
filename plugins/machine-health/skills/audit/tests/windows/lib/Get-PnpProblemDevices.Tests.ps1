#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-PnpProblemDevices.ps1'
}

Describe 'Get-PnpProblemDevice' -Tag 'lib' {
    AfterEach {
        # Remove the pnputil stub; AfterEach runs even after a failed assertion, so it never leaks.
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
        # Shadow pnputil as a function: the call operator dispatches to a same-named
        # function in scope before the native command.
        function script:pnputil {
            # spellchecker:off
            @'
Microsoft PnP Utility

No devices match the specified filter.
'@
            # spellchecker:on
        }
        Mock Get-Command { [pscustomobject]@{ Name = 'pnputil' } } -ParameterFilter { $Name -eq 'pnputil' }
        $result = @(Get-PnpProblemDevice)
        $result.Count | Should -Be 0
    }

    It 'parses real device blocks and skips the preamble' {
        function script:pnputil {
            # spellchecker:off
            @'
Microsoft PnP Utility

Instance ID: ACPI\MOCK\0000
Device Description: Mock Device
Class Name: Display
Problem Code: 10 (CM_PROB_FAILED_START)
Problem Status: 0xC0000001
'@
            # spellchecker:on
        }
        Mock Get-Command { [pscustomobject]@{ Name = 'pnputil' } } -ParameterFilter { $Name -eq 'pnputil' }
        $result = @(Get-PnpProblemDevice)
        $result.Count | Should -Be 1
        $result[0].instance_id | Should -Be 'ACPI\MOCK\0000'
        $result[0].problem_code | Should -Be 10
    }
}
