#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/checks/Test-WindowsUpdate.ps1.

.DESCRIPTION
Pins the fixes landing in Phase 5f:

1. PFRO (PendingFileRenameOperations) value-array bug. The previous
   code used `$null -ne (Get-ItemProperty ...)` to test for pending
   operations -- but the property usually EXISTS even on freshly-booted
   machines, just with an empty value array. That produced a permanent
   reboot_pending=true on most Windows machines.

2. Pending-reboot signals with test isolation: tests mock Test-Path /
   Get-ItemProperty directly to simulate registry state.

3. A degraded update enumeration (PSWindowsUpdate present but Get-WUList
   throws) surfaces as INFO, not a misleading OK 'no pending updates'.
#>

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:SkillRoot = Split-Path -Parent $script:TestsRoot
    $script:ScriptPath = Join-Path $script:SkillRoot 'scripts\windows\checks\Test-WindowsUpdate.ps1'
    $script:LibRoot = Join-Path $script:SkillRoot 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Assert-CheckResult.ps1')
    Import-Module (Join-Path $script:TestsRoot 'helpers\Mock-Helpers.psm1') -Force

    function Invoke-WindowsUpdateAsObject {
        $raw = & $script:ScriptPath
        $json = ($raw | Where-Object { $_ }) -join "`n"
        return $json | ConvertFrom-Json
    }
}

Describe 'Test-WindowsUpdate -- baseline' -Tag 'check' {
    BeforeAll {
        Mock Get-HotFix { @() }
        Mock Test-Path { $false }
        Mock Get-ItemProperty -ParameterFilter { $Name -eq 'PendingFileRenameOperations' } -MockWith {
            [pscustomobject]@{ PendingFileRenameOperations = @() }
        }
        Mock Get-Module { $null }
    }

    It 'emits a schema-valid CheckResult' {
        $result = Invoke-WindowsUpdateAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.id | Should -Be 'windows-update'
    }

    It 'reports OK when nothing is pending and no reboot signals are set' {
        $result = Invoke-WindowsUpdateAsObject
        $result.severity | Should -Be 'OK'
        $result.detail.reboot_pending | Should -BeFalse
    }
}

Describe 'Test-WindowsUpdate -- PFRO value-array regression' -Tag 'check' {
    It 'does NOT flag reboot pending when PendingFileRenameOperations exists but value is empty' {
        Mock Get-HotFix { @() }
        Mock Test-Path { $false }
        # The key scenario: the registry property exists (so $null -ne $pfro),
        # but its value-array is empty. The previous code flagged this as
        # reboot_pending=true, which fired on most healthy machines.
        Mock Get-ItemProperty -ParameterFilter { $Name -eq 'PendingFileRenameOperations' } -MockWith {
            [pscustomobject]@{ PendingFileRenameOperations = @() }
        }
        Mock Get-Module { $null }

        $result = Invoke-WindowsUpdateAsObject
        $result.detail.reboot_pending | Should -BeFalse
        $result.detail.reboot_sources.pfro | Should -BeFalse
    }

    It 'flags reboot pending when PendingFileRenameOperations has non-empty entries' {
        Mock Get-HotFix { @() }
        Mock Test-Path { $false }
        Mock Get-ItemProperty -ParameterFilter { $Name -eq 'PendingFileRenameOperations' } -MockWith {
            [pscustomobject]@{
                PendingFileRenameOperations = @(
                    '\??\C:\Windows\Temp\foo.dll'
                    ''
                )
            }
        }
        Mock Get-Module { $null }

        $result = Invoke-WindowsUpdateAsObject
        $result.detail.reboot_pending | Should -BeTrue
        $result.detail.reboot_sources.pfro | Should -BeTrue
        $result.severity | Should -Be 'INFO'
    }

    It 'treats missing PendingFileRenameOperations property as no pending ops' {
        Mock Get-HotFix { @() }
        Mock Test-Path { $false }
        # Property genuinely absent -- Get-ItemProperty throws PropertyNotFound.
        Mock Get-ItemProperty -ParameterFilter { $Name -eq 'PendingFileRenameOperations' } -MockWith {
            throw [System.Management.Automation.PSArgumentException]::new(
                "Property 'PendingFileRenameOperations' does not exist")
        }
        Mock Get-Module { $null }

        $result = Invoke-WindowsUpdateAsObject
        $result.detail.reboot_sources.pfro | Should -BeFalse
    }
}

Describe 'Test-WindowsUpdate -- CBS and WU reboot signals' -Tag 'check' {
    It 'flags INFO when CBS RebootPending is set' {
        Mock Get-HotFix { @() }
        Mock Test-Path -ParameterFilter {
            $Path -like '*Component Based Servicing\RebootPending'
        } -MockWith { $true }
        Mock Test-Path -MockWith { $false }
        Mock Get-ItemProperty -ParameterFilter { $Name -eq 'PendingFileRenameOperations' } -MockWith {
            [pscustomobject]@{ PendingFileRenameOperations = @() }
        }
        Mock Get-Module { $null }

        $result = Invoke-WindowsUpdateAsObject
        $result.severity | Should -Be 'INFO'
        $result.detail.reboot_sources.cbs | Should -BeTrue
    }

    It 'flags INFO when WindowsUpdate RebootRequired is set' {
        Mock Get-HotFix { @() }
        Mock Test-Path -ParameterFilter {
            $Path -like '*WindowsUpdate\Auto Update\RebootRequired'
        } -MockWith { $true }
        Mock Test-Path -MockWith { $false }
        Mock Get-ItemProperty -ParameterFilter { $Name -eq 'PendingFileRenameOperations' } -MockWith {
            [pscustomobject]@{ PendingFileRenameOperations = @() }
        }
        Mock Get-Module { $null }

        $result = Invoke-WindowsUpdateAsObject
        $result.severity | Should -Be 'INFO'
        $result.detail.reboot_sources.wu | Should -BeTrue
    }
}

Describe 'Test-WindowsUpdate -- degraded enumeration' -Tag 'check' {
    BeforeAll {
        # Get-WUList ships with the PSWindowsUpdate module, absent in CI/dev.
        # Define a stub so Mock can attach; the check resolves it from this
        # (parent) scope when invoked via `& $ScriptPath`.
        function Get-WUList { }
    }

    It 'reports INFO (degraded), not OK, when PSWindowsUpdate is present but Get-WUList fails' {
        Mock Get-HotFix { @() }
        Mock Test-Path { $false }
        Mock Get-ItemProperty -ParameterFilter { $Name -eq 'PendingFileRenameOperations' } -MockWith {
            [pscustomobject]@{ PendingFileRenameOperations = @() }
        }
        Mock Get-Module { [pscustomobject]@{ Name = 'PSWindowsUpdate'; Version = [version]'2.2.0' } }
        Mock Get-WUList { throw 'WUApiLib COM error 0x80240438' }

        $result = Invoke-WindowsUpdateAsObject
        $result.severity | Should -Be 'INFO'
        $result.detail.update_enum_degraded | Should -BeTrue
        $result.summary | Should -Match 'degraded'
        # The check itself ran: reboot signals are valid, so ran_successfully stays true.
        $result.ran_successfully | Should -BeTrue
        # pending_update_count is null (not 0) so the degraded run does not persist
        # a false "no pending updates" into the windows-update trend metric.
        $result.detail.pending_update_count | Should -BeNullOrEmpty
    }

    It 'stays OK when the module is absent (reboot-signals-only fallback, not degraded)' {
        Mock Get-HotFix { @() }
        Mock Test-Path { $false }
        Mock Get-ItemProperty -ParameterFilter { $Name -eq 'PendingFileRenameOperations' } -MockWith {
            [pscustomobject]@{ PendingFileRenameOperations = @() }
        }
        Mock Get-Module { $null }

        $result = Invoke-WindowsUpdateAsObject
        $result.severity | Should -Be 'OK'
        $result.detail.update_enum_degraded | Should -BeFalse
    }
}

Describe 'Test-WindowsUpdate -- failure modes' -Tag 'check' {
    It 'degrades gracefully when Get-HotFix fails' {
        Mock Get-HotFix { throw 'SCM access denied' }
        Mock Test-Path { $false }
        Mock Get-ItemProperty -ParameterFilter { $Name -eq 'PendingFileRenameOperations' } -MockWith {
            [pscustomobject]@{ PendingFileRenameOperations = @() }
        }
        Mock Get-Module { $null }

        $result = Invoke-WindowsUpdateAsObject
        # Get-HotFix failure is non-fatal -- reboot signals still run.
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.ran_successfully | Should -BeTrue
        @($result.detail.recent_hotfixes).Count | Should -Be 0
    }
}
