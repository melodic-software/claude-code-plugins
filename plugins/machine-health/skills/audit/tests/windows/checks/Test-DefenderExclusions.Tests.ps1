#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    # The adapter and Test-IsElevated are dot-sourced here so Mock can intercept
    # them; the check script's own imports are not visible in this scope.
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -Check 'Test-DefenderExclusions' `
        -AsObject 'Invoke-DefenderExclusionsAsObject' `
        -LibScript 'Test-IsElevated.ps1', 'New-FindingItem.ps1', 'New-DefenderExclusionItem.ps1', 'Get-DefenderExclusionState.ps1',
        'Get-DefenderEventHistory.ps1' -MockHelpers

    function Invoke-DefenderExclusionWithMuteList {
        param([string[]] $MutedKeys)
        ConvertFrom-CheckOutput (& $script:ScriptPath -MutedKeys $MutedKeys)
    }
}

Describe 'Test-DefenderExclusions -- masked lists' -Tag 'check' {
    It 'reports UNKNOWN + needs_admin with list_state masked and no items, never OK' {
        Mock Test-IsElevated { $false }
        Mock Get-DefenderExclusionState {
            [pscustomobject]@{ ReadState = 'masked'; Paths = @(); Extensions = @(); Processes = @() }
        }
        $result = Invoke-DefenderExclusionsAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.severity | Should -Be 'UNKNOWN'
        $result.needs_admin | Should -BeTrue
        $result.ran_successfully | Should -BeFalse
        $result.error | Should -Be 'needs_admin'
        $result.detail.admin_fields | Should -Contain 'unexpected_path_count'
        $result.detail.elevated | Should -BeFalse
        $result.detail.list_state | Should -Be 'masked'
        $result.detail.items_count | Should -Be 0
        $result.detail.muted_count | Should -Be 0
        @($result.detail.items).Count | Should -Be 0
    }
}

Describe 'Test-DefenderExclusions -- baseline' -Tag 'check' {
    It 'emits a schema-valid CheckResult with zero exclusions' {
        Mock Get-DefenderExclusionState {
            [pscustomobject]@{ ReadState = 'ok'; Paths = @(); Extensions = @(); Processes = @() }
        }
        $result = Invoke-DefenderExclusionsAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.id | Should -Be 'defender-exclusions'
        $result.severity | Should -Be 'OK'
        $result.detail.list_state | Should -Be 'ok'
        $result.detail.exclusion_path_count | Should -Be 0
        $result.detail.unexpected_path_count | Should -Be 0
        $result.detail.items_count | Should -Be 0
        # Admin-gated checks must keep needs_admin=true even when run elevated
        # so downstream tooling consistently classifies coverage. Mirrors TPM.
        $result.needs_admin | Should -BeTrue
    }

    It 'reports UNKNOWN with the read state when the preference read fails' {
        Mock Get-DefenderExclusionState {
            [pscustomobject]@{ ReadState = 'error'; Paths = @(); Extensions = @(); Processes = @() }
        }
        $result = Invoke-DefenderExclusionsAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.severity | Should -Be 'UNKNOWN'
        $result.ran_successfully | Should -BeFalse
        $result.needs_admin | Should -BeTrue
        $result.detail.list_state | Should -Be 'error'
    }
}

Describe 'Test-DefenderExclusions -- severity rubric' -Tag 'check' {
    It 'reports INFO when only well-known dev paths are excluded' {
        Mock Get-DefenderExclusionState {
            [pscustomobject]@{
                ReadState  = 'ok'
                Paths      = @('<drive>:\Profile\.dotnet', '<drive>:\Profile\project\node_modules')
                Extensions = @()
                Processes  = @()
            }
        }
        $result = Invoke-DefenderExclusionsAsObject
        $result.severity | Should -Be 'INFO' -Because $result.error
        $result.detail.unexpected_path_count | Should -Be 0
        @($result.detail.items | Where-Object expected).Count | Should -Be 2
    }

    It 'reports WARN when an unexpected path is excluded' {
        Mock Get-DefenderExclusionState {
            [pscustomobject]@{ ReadState = 'ok'; Paths = @('<drive>:\sketchy\folder'); Extensions = @(); Processes = @() }
        }
        $result = Invoke-DefenderExclusionsAsObject
        $result.severity | Should -Be 'WARN' -Because $result.error
        $result.detail.unexpected_path_count | Should -Be 1
        $item = @($result.detail.items)[0]
        $item.severity | Should -Be 'WARN'
        $item.expected | Should -BeFalse
    }

    It 'lists extension and process exclusions as INFO items' {
        Mock Get-DefenderExclusionState {
            [pscustomobject]@{ ReadState = 'ok'; Paths = @(); Extensions = @('.tmp'); Processes = @('tool.exe') }
        }
        $result = Invoke-DefenderExclusionsAsObject
        $result.severity | Should -Be 'INFO'
        $result.detail.exclusion_extension_count | Should -Be 1
        $result.detail.exclusion_process_count | Should -Be 1
        $result.detail.items_count | Should -Be 2
        ($result.detail.items | Where-Object exclusion_type -EQ 'process').value | Should -Be 'tool.exe'
    }

    It 'counts a muted unexpected path as expected and does not raise severity' {
        Mock Get-DefenderExclusionState {
            [pscustomobject]@{ ReadState = 'ok'; Paths = @('<drive>:\sketchy\folder'); Extensions = @(); Processes = @() }
        }
        $result = Invoke-DefenderExclusionWithMuteList -MutedKeys @(Get-FindingKey -Kind 'exclusion' -Identity 'path', '<drive>:\sketchy\folder')
        $result.severity | Should -Be 'OK'
        $result.detail.unexpected_path_count | Should -Be 0
        $result.detail.muted_count | Should -Be 1
        @($result.detail.items)[0].muted | Should -BeTrue
    }

    It 'keys an exclusion exactly as defender keys its 5007 history, so one mute covers both checks' {
        Mock Get-DefenderExclusionState {
            [pscustomobject]@{ ReadState = 'ok'; Paths = @('X:\Build'); Extensions = @(); Processes = @() }
        }
        Mock Get-MpComputerStatus { New-MockDefenderComputerStatus }
        Mock Get-DefenderEventHistory {
            [pscustomobject]@{
                ReadState = 'ok'; LogOldestRecord = (Get-Date).AddDays(-90); SkippedRecords = 0; Detections = @()
                ExclusionChanges = @([pscustomobject]@{ Type = 'path'; Value = 'X:\build'; Change = 'added'; ChangedAt = (Get-Date).AddDays(-40) })
            }
        }
        $defenderPath = Join-Path (Split-Path $script:ScriptPath) 'Test-Defender.ps1'

        $current = @((Invoke-DefenderExclusionsAsObject).detail.items)[0].key
        $history = @((Invoke-CheckScriptAsObject $defenderPath).detail.items)[0].key
        $current | Should -Match '^exclusion:[0-9a-f]{16}$'
        $history | Should -Be $current
    }
}
