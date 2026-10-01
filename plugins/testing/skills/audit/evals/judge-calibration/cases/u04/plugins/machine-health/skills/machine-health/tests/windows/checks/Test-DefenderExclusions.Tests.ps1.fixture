#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:SkillRoot = Split-Path -Parent $script:TestsRoot
    $script:ScriptPath = Join-Path $script:SkillRoot 'scripts\windows\checks\Test-DefenderExclusions.ps1'
    $script:LibRoot = Join-Path $script:SkillRoot 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Assert-CheckResult.ps1')
    # Dot-source Test-IsElevated so Pester's Mock can intercept it. The check
    # script itself imports the file from its own scope, but that doesn't make
    # the function visible here; we need our own copy to mock against.
    . (Join-Path $script:LibRoot 'Test-IsElevated.ps1')

    function Invoke-DefenderExclusionsAsObject {
        $raw = & $script:ScriptPath
        $json = ($raw | Where-Object { $_ }) -join "`n"
        return $json | ConvertFrom-Json
    }
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
