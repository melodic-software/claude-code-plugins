#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    # Test-IsElevated is dot-sourced here so Mock can intercept it; the check script's
    # own import is not visible in this scope.
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -Check 'Test-DefenderExclusions' `
        -AsObject 'Invoke-DefenderExclusionsAsObject' -LibScript 'Test-IsElevated.ps1'
}

Describe 'Test-DefenderExclusions -- elevation gate' -Tag 'check' {
    It 'reports UNKNOWN + needs_admin when non-elevated' {
        Mock Test-IsElevated { $false }
        # Get-MpPreference must NOT be called when the gate trips; mock it as
        # throwing so a regression that bypasses the gate fails loudly.
        Mock Get-MpPreference { throw 'Should not be reached when non-elevated' }
        $result = Invoke-DefenderExclusionsAsObject
        $result.severity | Should -Be 'UNKNOWN'
        $result.needs_admin | Should -BeTrue
        $result.ran_successfully | Should -BeFalse
        $result.error | Should -Be 'needs_admin'
        $result.detail.admin_fields | Should -Contain 'unexpected_path_count'
    }
}

Describe 'Test-DefenderExclusions -- baseline' -Tag 'check' {
    It 'emits a schema-valid CheckResult with zero exclusions' {
        Mock Test-IsElevated { $true }
        Mock Get-MpPreference {
            [pscustomobject]@{
                ExclusionPath      = @()
                ExclusionExtension = @()
                ExclusionProcess   = @()
            }
        }
        $result = Invoke-DefenderExclusionsAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.id | Should -Be 'defender-exclusions'
        $result.severity | Should -Be 'OK'
        # Admin-gated checks must keep needs_admin=true even when run elevated
        # so downstream tooling consistently classifies coverage. Mirrors TPM.
        $result.needs_admin | Should -BeTrue
    }

    It 'reports UNKNOWN when Get-MpPreference is unavailable' {
        Mock Test-IsElevated { $true }
        Mock Get-MpPreference { throw 'Defender API unavailable' }
        $result = Invoke-DefenderExclusionsAsObject
        $result.severity | Should -Be 'UNKNOWN'
        $result.ran_successfully | Should -BeFalse
        # Admin-gated checks must keep needs_admin=true on the API-unavailable
        # path too, so downstream coverage tooling stays consistent.
        $result.needs_admin | Should -BeTrue
    }
}

Describe 'Test-DefenderExclusions -- severity rubric' -Tag 'check' {
    It 'reports INFO when only well-known dev paths are excluded' {
        Mock Test-IsElevated { $true }
        Mock Get-MpPreference {
            # Pester 5 mock bodies don't reliably see $script:* vars; build
            # placeholder paths locally. [char]92 = backslash.
            $sep = [char]92
            [pscustomobject]@{
                ExclusionPath      = @(
                    "<drive>:${sep}Users${sep}<user>${sep}.dotnet"
                    "<drive>:${sep}Users${sep}<user>${sep}project${sep}node_modules"
                )
                ExclusionExtension = @()
                ExclusionProcess   = @()
            }
        }
        $result = Invoke-DefenderExclusionsAsObject
        $result.severity | Should -Be 'INFO' -Because $result.error
        $result.detail.unexpected_path_count | Should -Be 0
    }

    It 'reports WARN when an unexpected path is excluded' {
        Mock Test-IsElevated { $true }
        Mock Get-MpPreference {
            $sep = [char]92
            [pscustomobject]@{
                ExclusionPath      = @("<drive>:${sep}sketchy${sep}folder")
                ExclusionExtension = @()
                ExclusionProcess   = @()
            }
        }
        $result = Invoke-DefenderExclusionsAsObject
        $result.severity | Should -Be 'WARN' -Because $result.error
        $result.detail.unexpected_path_count | Should -Be 1
    }
}
