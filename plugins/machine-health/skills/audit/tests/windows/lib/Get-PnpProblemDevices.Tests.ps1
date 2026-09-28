#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-PnpProblemDevices.ps1'

    function New-PnpNativeResult {
        param(
            [string] $Status = 'Ok',
            [string] $Output = '',
            [int] $ExitCode = 0
        )
        [pscustomobject]@{
            status    = $Status
            source    = $(if ($Status -eq 'Absent') { 'absent' } else { 'pnputil' })
            exit_code = $(if ($Status -eq 'Absent') { $null } else { $ExitCode })
            output    = $Output
            error     = $(if ($Status -eq 'Failed') { 'pnputil failed' } else { $null })
        }
    }
}

Describe 'Get-PnpProblemDevice' -Tag 'lib' {
    It 'returns empty array when pnputil is not on PATH' {
        Mock Invoke-NativeCommand { New-PnpNativeResult -Status 'Absent' } -ParameterFilter {
            $Name -eq 'pnputil'
        }
        $result = @(Get-PnpProblemDevice)
        $result.Count | Should -Be 0
    }

    It 'passes enum-devices and problem as two argv entries' {
        Mock Invoke-NativeCommand { New-PnpNativeResult } -ParameterFilter { $Name -eq 'pnputil' }
        $null = Get-PnpProblemDevice
        Should -Invoke Invoke-NativeCommand -Times 1 -ParameterFilter {
            $Name -eq 'pnputil' -and
            @($ArgumentList).Count -eq 2 -and
            @($ArgumentList)[0] -eq '/enum-devices' -and
            @($ArgumentList)[1] -eq '/problem'
        }
    }

    It 'ignores pnputil preamble banner when no devices have problems (regression)' {
        Mock Invoke-NativeCommand {
            New-PnpNativeResult -Output @"
Microsoft PnP Utility

No devices match the specified filter.
"@
        } -ParameterFilter { $Name -eq 'pnputil' }
        $result = @(Get-PnpProblemDevice)
        $result.Count | Should -Be 0
    }

    It 'parses real device blocks and skips the preamble' {
        Mock Invoke-NativeCommand {
            New-PnpNativeResult -Output @"
Microsoft PnP Utility

Instance ID: ACPI\MOCK\0000
Device Description: Mock Device
Class Name: Display
Problem Code: 10 (CM_PROB_FAILED_START)
Problem Status: 0xC0000001
"@
        } -ParameterFilter { $Name -eq 'pnputil' }
        $result = @(Get-PnpProblemDevice)
        $result.Count | Should -Be 1
        $result[0].instance_id | Should -Be 'ACPI\MOCK\0000'
        $result[0].problem_code | Should -Be 10
    }

    It 'returns empty when pnputil exits non-zero' {
        Mock Invoke-NativeCommand {
            New-PnpNativeResult -Status 'NonZero' -ExitCode 1 -Output @'
Instance ID: ACPI\MOCK\0000
Device Description: Mock Device
Problem Code: 10
'@
        } -ParameterFilter { $Name -eq 'pnputil' }
        $result = @(Get-PnpProblemDevice)
        $result.Count | Should -Be 0
    }
}
