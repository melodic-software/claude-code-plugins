#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:SkillRoot = Split-Path -Parent $script:TestsRoot
    $script:ScriptPath = Join-Path $script:SkillRoot 'scripts\windows\checks\Test-TpmBitLocker.ps1'
    $script:LibRoot = Join-Path $script:SkillRoot 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Assert-CheckResult.ps1')
    . (Join-Path $script:LibRoot 'Test-IsElevated.ps1')

    function Invoke-TpmBitLockerAsObject {
        $raw = & $script:ScriptPath
        $json = ($raw | Where-Object { $_ }) -join "`n"
        return $json | ConvertFrom-Json
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
        Mock Get-BitLockerVolume {
            @([pscustomobject]@{
                    MountPoint       = 'C:'
                    VolumeType       = 'OperatingSystem'
                    ProtectionStatus = 'On'
                    EncryptionMethod = 'XtsAes256'
                    VolumeStatus     = 'FullyEncrypted'
                })
        }
        $result = Invoke-TpmBitLockerAsObject
        $result.severity | Should -Be 'OK' -Because $result.error
    }

    It 'reports WARN when TPM is not owned' {
        Mock Test-IsElevated { $true }
        Mock Get-Tpm { [pscustomobject]@{ TpmOwned = $false; TpmEnabled = $true } }
        Mock Get-BitLockerVolume {
            @([pscustomobject]@{
                    MountPoint       = 'C:'
                    VolumeType       = 'OperatingSystem'
                    ProtectionStatus = 'On'
                    EncryptionMethod = 'XtsAes256'
                    VolumeStatus     = 'FullyEncrypted'
                })
        }
        $result = Invoke-TpmBitLockerAsObject
        $result.severity | Should -Be 'WARN' -Because $result.error
    }

    It 'reports WARN when BitLocker is off on the system volume' {
        Mock Test-IsElevated { $true }
        Mock Get-Tpm { [pscustomobject]@{ TpmOwned = $true; TpmEnabled = $true } }
        Mock Get-BitLockerVolume {
            @([pscustomobject]@{
                    MountPoint       = 'C:'
                    VolumeType       = 'OperatingSystem'
                    ProtectionStatus = 'Off'
                    EncryptionMethod = 'None'
                    VolumeStatus     = 'FullyDecrypted'
                })
        }
        $result = Invoke-TpmBitLockerAsObject
        $result.severity | Should -Be 'WARN' -Because $result.error
    }
}
