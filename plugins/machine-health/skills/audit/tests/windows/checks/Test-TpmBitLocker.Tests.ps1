#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -Check 'Test-TpmBitLocker' `
        -AsObject 'Invoke-TpmBitLockerAsObject' -LibScript 'Test-IsElevated.ps1'

    function New-MockBitLockerVolume {
        param(
            [string] $ProtectionStatus = 'On',
            [string] $EncryptionMethod = 'XtsAes256',
            [string] $VolumeStatus = 'FullyEncrypted'
        )
        [pscustomobject]@{
            MountPoint       = 'C:'
            VolumeType       = 'OperatingSystem'
            ProtectionStatus = $ProtectionStatus
            EncryptionMethod = $EncryptionMethod
            VolumeStatus     = $VolumeStatus
        }
    }
}

Describe 'Test-TpmBitLocker -- elevation gate' -Tag 'check' {
    It 'reports UNKNOWN + needs_admin when non-elevated' {
        Mock Test-IsElevated { $false }
        $result = Invoke-TpmBitLockerAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.id | Should -Be 'tpm-bitlocker'
        $result.severity | Should -Be 'UNKNOWN'
        $result.needs_admin | Should -BeTrue
        $result.ran_successfully | Should -BeFalse
    }
}

Describe 'Test-TpmBitLocker -- severity rubric (elevated)' -Tag 'check' {
    It 'reports OK when TPM is owned+enabled and system volume is protected' {
        Mock Test-IsElevated { $true }
        Mock Get-Tpm { [pscustomobject]@{ TpmOwned = $true; TpmEnabled = $true } }
        Mock Get-BitLockerVolume { @(New-MockBitLockerVolume) }
        $result = Invoke-TpmBitLockerAsObject
        $result.severity | Should -Be 'OK' -Because $result.error
    }

    It 'reports WARN when TPM is not owned' {
        Mock Test-IsElevated { $true }
        Mock Get-Tpm { [pscustomobject]@{ TpmOwned = $false; TpmEnabled = $true } }
        Mock Get-BitLockerVolume { @(New-MockBitLockerVolume) }
        $result = Invoke-TpmBitLockerAsObject
        $result.severity | Should -Be 'WARN' -Because $result.error
    }

    It 'reports WARN when BitLocker is off on the system volume' {
        Mock Test-IsElevated { $true }
        Mock Get-Tpm { [pscustomobject]@{ TpmOwned = $true; TpmEnabled = $true } }
        Mock Get-BitLockerVolume {
            @(New-MockBitLockerVolume -ProtectionStatus 'Off' `
                    -EncryptionMethod 'None' -VolumeStatus 'FullyDecrypted')
        }
        $result = Invoke-TpmBitLockerAsObject
        $result.severity | Should -Be 'WARN' -Because $result.error
    }
}
