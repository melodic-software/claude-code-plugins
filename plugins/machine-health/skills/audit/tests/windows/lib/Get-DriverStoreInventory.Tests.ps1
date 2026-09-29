#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-DriverStoreInventory.ps1'

    function New-DriverNativeResult {
        param(
            [string] $Status = 'Ok',
            [string] $Output = ''
        )
        [pscustomobject]@{
            status    = $Status
            source    = $(if ($Status -eq 'Absent') { 'absent' } else { 'pnputil' })
            exit_code = $(if ($Status -eq 'Ok') { 0 } elseif ($Status -eq 'NonZero') { 1 } else { $null })
            output    = $Output
            error     = $null
        }
    }
}

Describe 'Get-DriverStoreInventory' -Tag 'lib' {
    It 'passes /enum-drivers as one argv entry' {
        Mock Invoke-NativeCommand { New-DriverNativeResult } -ParameterFilter { $Name -eq 'pnputil' }
        $null = Get-DriverStoreInventory
        Should -Invoke Invoke-NativeCommand -Times 1 -ParameterFilter {
            $Name -eq 'pnputil' -and
            @($ArgumentList).Count -eq 1 -and
            @($ArgumentList)[0] -eq '/enum-drivers'
        }
    }

    It 'parses a driver record and skips the header block' {
        Mock Invoke-NativeCommand {
            New-DriverNativeResult -Output @'
Microsoft PnP Utility

Published Name:     oem1.inf
Original Name:      mock.inf
Provider Name:      Mock
Class Name:         Display
Driver Version:     1.0.0.0
Signer Name:        Microsoft Windows
'@
        } -ParameterFilter { $Name -eq 'pnputil' }

        $result = @(Get-DriverStoreInventory)
        $result.Count | Should -Be 1
        $result[0].PublishedName | Should -Be 'oem1.inf'
        $result[0].SignerName | Should -Be 'Microsoft Windows'
    }

    It 'returns empty when pnputil is absent or exits non-zero' {
        Mock Invoke-NativeCommand { New-DriverNativeResult -Status 'Absent' } -ParameterFilter {
            $Name -eq 'pnputil'
        }
        @(Get-DriverStoreInventory).Count | Should -Be 0

        Mock Invoke-NativeCommand {
            New-DriverNativeResult -Status 'NonZero' -Output @'
Published Name:     oem1.inf
Signer Name:
'@
        } -ParameterFilter { $Name -eq 'pnputil' }
        @(Get-DriverStoreInventory).Count | Should -Be 0
    }
}
