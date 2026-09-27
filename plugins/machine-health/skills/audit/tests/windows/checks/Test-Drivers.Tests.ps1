#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/checks/Test-Drivers.ps1.

.DESCRIPTION
Pins the rubric:

1. IsSigned=false is not a WARN trigger. It produces false
   positives on modern Windows 10/11 -- cross-signed, attestation-
   signed, and user-mode drivers routinely report false. Secure Boot
   already blocks genuinely-unsigned kernel drivers from loading, so
   IsSigned=false in WMI is a noise signal.

2. New real signals:
   - pnputil /enum-drivers SignerName empty: the driver store has no
     recorded signer (the authoritative "unsigned" condition).
   - CodeIntegrity event log 3001/3004 within 7 days: Windows kernel
     rejected driver loads due to signature violations.

3. Age signal stays at INFO (drivers >3 years old are a weak signal --
   many OEM drivers are very old but still correct).

## Testing architecture note

Pester mocks of dot-sourced user functions (Get-DriverStoreInventory,
Get-PnpProblemDevice, Test-IsElevated) do NOT propagate through
`& $scriptPath` script invocation -- the call operator launches the
script in a scope where the mock isn't visible (Pester issue #515,
confirmed by maintainer nohwnd). The check script exposes
Invoke-DriversCheck and uses a `$MyInvocation.InvocationName -eq '.'`
guard so tests can dot-source it and call the function directly, with
mocks applying in the test scope.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -Check 'Test-Drivers' -MockHelpers

    # Dot-source the check script so Invoke-DriversCheck and its lib functions are defined
    # here; the script's InvocationName guard skips its main body.
    . $script:ScriptPath

    function Invoke-DriversAsObject {
        return Invoke-DriversCheck
    }

    function New-DriverStoreRecord {
        param(
            [string] $PublishedName = 'oem1.inf',
            [string] $OriginalName = 'device.inf',
            [string] $ProviderName = 'Intel',
            [string] $ClassName = 'System',
            [string] $DriverVersion = '1.0.0.0',
            [string] $SignerName = 'Microsoft Windows Hardware Compatibility Publisher',
            [string] $Date = '01/01/2024'
        )
        [pscustomobject]@{
            PublishedName = $PublishedName
            OriginalName  = $OriginalName
            ProviderName  = $ProviderName
            ClassName     = $ClassName
            DriverVersion = $DriverVersion
            SignerName    = $SignerName
            Date          = $Date
        }
    }
}

Describe 'Test-Drivers -- healthy baseline' -Tag 'check' {
    BeforeAll {
        # spellchecker:ignore-next-line
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PnPSignedDriver' } -MockWith {
            $nic = New-MockDriver -DeviceName 'Intel(R) NIC' -DriverVersion '12.0.0.0' `
                -DriverDate (Get-Date).AddYears(-1) -IsSigned $true
            $gpu = New-MockDriver -DeviceName 'NVIDIA GPU' -DriverVersion '550.0.0.0' `
                -DriverDate (Get-Date).AddMonths(-3) -IsSigned $true
            @($nic, $gpu)
        }
        Mock Get-DriverStoreInventory {
            @(
                New-DriverStoreRecord -PublishedName 'oem1.inf'
                New-DriverStoreRecord -PublishedName 'oem2.inf'
            )
        }
        Mock Get-WinEvent { @() }
        # Simulate elevated so Get-PnpProblemDevice runs (returns empty below) instead of
        # being skipped and populating $adminFields.
        Mock Test-IsElevated { $true }
        Mock Get-PnpProblemDevice { @() }
        # Short-circuit side-effecting calls (Win32_VideoController CIM, PATH probe,
        # PSWindowsUpdate enumeration) so tests do not pay for them on CI.
        Mock Get-Module { $null }
        Mock Get-GpuDriverInfo { @() }
        Mock Get-VendorUpdateCli { @() }
    }

    It 'emits a schema-valid CheckResult' {
        $result = Invoke-DriversAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.id | Should -Be 'drivers'
    }

    It 'reports OK when all drivers are signed and no CodeIntegrity events fired' {
        $result = Invoke-DriversAsObject
        $result.severity | Should -Be 'OK'
    }
}

Describe 'Test-Drivers -- IsSigned=false is no longer a WARN trigger' -Tag 'check' {
    BeforeAll {
        # WMI reports IsSigned=false for multiple drivers (common on dev machines).
        # spellchecker:ignore-next-line
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PnPSignedDriver' } -MockWith {
            $nic = New-MockDriver -DeviceName 'Intel(R) NIC' -DriverVersion '12.0.0.0' `
                -DriverDate (Get-Date).AddYears(-1) -IsSigned $false
            $gpu = New-MockDriver -DeviceName 'NVIDIA GPU' -DriverVersion '550.0.0.0' `
                -DriverDate (Get-Date).AddMonths(-3) -IsSigned $false
            @($nic, $gpu)
        }
        # But pnputil reports every driver has a valid SignerName -- no genuinely unsigned.
        Mock Get-DriverStoreInventory {
            @(
                (New-DriverStoreRecord -PublishedName 'oem1.inf' `
                    -SignerName 'Microsoft Windows Hardware Compatibility Publisher')
                (New-DriverStoreRecord -PublishedName 'oem2.inf' -SignerName 'NVIDIA Corporation')
            )
        }
        Mock Get-WinEvent { @() }
        Mock Test-IsElevated { $true }
        Mock Get-PnpProblemDevice { @() }
        Mock Get-Module { $null }
        Mock Get-GpuDriverInfo { @() }
        Mock Get-VendorUpdateCli { @() }
    }

    It 'does not flag WMI IsSigned=false as a finding' {
        $result = Invoke-DriversAsObject
        # WMI IsSigned is noise -- SignerName from pnputil is the
        # authoritative signal.
        $result.severity | Should -Be 'OK'
    }
}

Describe 'Test-Drivers -- pnputil SignerName signal' -Tag 'check' {
    It 'WARNs when a driver has an empty SignerName in pnputil output' {
        # spellchecker:ignore-next-line
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PnPSignedDriver' } -MockWith {
            @(New-MockDriver -DeviceName 'Dodgy driver' -IsSigned $true)
        }
        Mock Get-DriverStoreInventory {
            @(
                New-DriverStoreRecord -PublishedName 'oem-ok.inf' -SignerName 'Microsoft'
                New-DriverStoreRecord -PublishedName 'oem-sketchy.inf' -SignerName ''
            )
        }
        Mock Get-WinEvent { @() }
        Mock Test-IsElevated { $true }
        Mock Get-PnpProblemDevice { @() }
        Mock Get-Module { $null }
        Mock Get-GpuDriverInfo { @() }
        Mock Get-VendorUpdateCli { @() }

        $result = Invoke-DriversAsObject
        $result.severity | Should -Be 'WARN'
        $result.detail.unsigned_in_store_count | Should -Be 1
    }
}

Describe 'Test-Drivers -- CodeIntegrity events' -Tag 'check' {
    It 'CRITs when CodeIntegrity 3001 fired in the last 7 days' {
        # spellchecker:ignore-next-line
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PnPSignedDriver' } -MockWith {
            @(New-MockDriver -DeviceName 'Any device')
        }
        Mock Get-DriverStoreInventory {
            @(New-DriverStoreRecord -SignerName 'Microsoft')
        }
        $e = New-MockEventLogRecord `
            -ProviderName 'Microsoft-Windows-CodeIntegrity' `
            -Id 3001 `
            -TimeCreated (Get-Date).AddDays(-1) `
            -LevelDisplayName 'Error' `
            -Message 'Code integrity determined that a file did not meet security requirements.'
        Mock Get-WinEvent { @($e) }.GetNewClosure()
        Mock Test-IsElevated { $true }
        Mock Get-PnpProblemDevice { @() }
        Mock Get-Module { $null }
        Mock Get-GpuDriverInfo { @() }
        Mock Get-VendorUpdateCli { @() }

        $result = Invoke-DriversAsObject
        # CodeIntegrity rejection means the kernel refused to load a
        # driver due to signature violations. Real signal.
        $result.severity | Should -Be 'CRIT'
        $result.detail.code_integrity_event_count | Should -Be 1
    }

    It 'ignores CodeIntegrity events older than 7 days' {
        # spellchecker:ignore-next-line
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PnPSignedDriver' } -MockWith {
            @(New-MockDriver -DeviceName 'Any device')
        }
        Mock Get-DriverStoreInventory {
            @(New-DriverStoreRecord -SignerName 'Microsoft')
        }
        $e = New-MockEventLogRecord `
            -ProviderName 'Microsoft-Windows-CodeIntegrity' `
            -Id 3001 `
            -TimeCreated (Get-Date).AddDays(-30) `
            -LevelDisplayName 'Error'
        Mock Get-WinEvent { @($e) }.GetNewClosure()
        Mock Test-IsElevated { $true }
        Mock Get-PnpProblemDevice { @() }
        Mock Get-Module { $null }
        Mock Get-GpuDriverInfo { @() }
        Mock Get-VendorUpdateCli { @() }

        $result = Invoke-DriversAsObject
        $result.severity | Should -Be 'OK'
    }
}

Describe 'Test-Drivers -- old-driver age signal' -Tag 'check' {
    It 'INFOs when a driver is older than 3 years' {
        # spellchecker:ignore-next-line
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PnPSignedDriver' } -MockWith {
            @(
                New-MockDriver -DeviceName 'Old RAID' -DriverDate (Get-Date).AddYears(-5) -IsSigned $true
                New-MockDriver -DeviceName 'Recent NIC' -DriverDate (Get-Date).AddMonths(-3) -IsSigned $true
            )
        }
        Mock Get-DriverStoreInventory {
            @(New-DriverStoreRecord -SignerName 'Microsoft')
        }
        Mock Get-WinEvent { @() }
        Mock Test-IsElevated { $true }
        Mock Get-PnpProblemDevice { @() }
        Mock Get-Module { $null }
        Mock Get-GpuDriverInfo { @() }
        Mock Get-VendorUpdateCli { @() }

        $result = Invoke-DriversAsObject
        $result.severity | Should -Be 'INFO'
        $result.detail.old_signed_count | Should -Be 1
    }
}

Describe 'Test-Drivers -- failure modes' -Tag 'check' {
    It 'emits UNKNOWN when Get-CimInstance fails' {
        # spellchecker:ignore-next-line
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PnPSignedDriver' } -MockWith {
            throw 'WMI provider failure'
        }
        Mock Get-DriverStoreInventory { @() }
        Mock Get-WinEvent { @() }
        Mock Test-IsElevated { $true }
        Mock Get-PnpProblemDevice { @() }

        $result = Invoke-DriversAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.severity | Should -Be 'UNKNOWN'
        $result.ran_successfully | Should -BeFalse
    }
}
