#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -Check 'Test-StartupItems' `
        -LibScript 'New-FindingItem.ps1', 'Read-StartupApproved.ps1', 'Get-RunKeyEntry.ps1', 'Get-LogonTaskInventory.ps1'

    function Invoke-StartupCheck {
        param([string[]] $MutedKeys = @())
        ConvertFrom-CheckOutput (& $script:ScriptPath -MutedKeys $MutedKeys)
    }

    function New-Read {
        param([string] $State = 'ok', [object[]] $Entries = @())
        [pscustomobject]@{ ReadState = $State; Entries = $Entries }
    }

    function New-Entry {
        param([string] $Kind, [string] $Scope, [string] $Name)
        [pscustomobject]@{ Kind = $Kind; Scope = $Scope; Name = $Name; Command = "X:\Apps\$Name.exe" }
    }

    # Every location empty and readable, no logon tasks, elevated.
    function Set-EmptyHost {
        Mock Get-RunKeyEntry { New-Read -State 'absent' }
        Mock Read-StartupApproved { [pscustomobject]@{ ReadState = 'absent'; Entries = @{} } }
        Mock Get-LogonTaskInventory { [pscustomobject]@{ ReadState = 'ok'; Complete = $true; Tasks = @() } }
    }

    $script:DisabledAt = [datetime]::new(2026, 1, 2, 3, 4, 5, [DateTimeKind]::Utc)

    function Set-PopulatedHost {
        Set-EmptyHost
        Mock Get-RunKeyEntry -ParameterFilter { $Scope -eq 'hkcu' -and $Key -eq 'Run' } {
            New-Read -Entries @(
                (New-Entry -Kind 'run' -Scope 'hkcu' -Name 'Updater'), (New-Entry -Kind 'run' -Scope 'hkcu' -Name 'Paused'),
                (New-Entry -Kind 'run' -Scope 'hkcu' -Name 'Odd'), (New-Entry -Kind 'run' -Scope 'hkcu' -Name 'Fresh')
            )
        }
        Mock Get-RunKeyEntry -ParameterFilter { $Scope -eq 'hklm' -and $Key -eq 'RunOnce' } {
            New-Read -Entries @(New-Entry -Kind 'runonce' -Scope 'hklm' -Name 'Setup')
        }
        Mock Get-RunKeyEntry -ParameterFilter { $Scope -eq 'user-folder' } {
            New-Read -Entries @(New-Entry -Kind 'startup-folder' -Scope 'user-folder' -Name 'Notes.lnk')
        }
        # The check runs the mock in its own script scope, so the time is captured here.
        $hkcuApproved = [pscustomobject]@{ ReadState = 'ok'; Entries = @{
                Updater = [pscustomobject]@{ State = 'enabled'; RawByte = $null; DisabledAt = $null }
                Paused  = [pscustomobject]@{ State = 'disabled'; RawByte = $null; DisabledAt = $script:DisabledAt }
                Odd     = [pscustomobject]@{ State = 'unknown'; RawByte = 1; DisabledAt = $null }
            }
        }
        Mock Read-StartupApproved -ParameterFilter { $Scope -eq 'hkcu' } ({ $hkcuApproved }.GetNewClosure())
        Mock Read-StartupApproved -ParameterFilter { $Scope -eq 'user-folder' } {
            [pscustomobject]@{ ReadState = 'ok'; Entries = @{
                    'Notes.lnk' = [pscustomobject]@{ State = 'enabled'; RawByte = $null; DisabledAt = $null }
                }
            }
        }
        Mock Get-LogonTaskInventory {
            [pscustomobject]@{ ReadState = 'ok'; Complete = $true; Tasks = @(
                    [pscustomobject]@{ TaskPath = '\Vendor\'; TaskName = 'Sync'; Command = 'sync.exe'; Enabled = $true }
                    [pscustomobject]@{ TaskPath = '\Vendor\'; TaskName = 'Old'; Command = 'old.exe'; Enabled = $false }
                )
            }
        }
    }
}

Describe 'Test-StartupItems' -Tag 'check' {
    It 'emits a schema-valid OK result when nothing starts at logon' {
        Set-EmptyHost

        $result = Invoke-StartupCheck

        { Assert-CheckResult $result } | Should -Not -Throw
        $result.id | Should -Be 'startup-items'
        $result.category | Should -Be 'services'
        $result.severity | Should -Be 'OK'
        $result.detail.items_count | Should -Be 0
        $result.detail.muted_count | Should -Be 0
    }

    Context 'a populated host' {
        BeforeEach { Set-PopulatedHost }

        It 'lists every Run, RunOnce, Startup-folder and logon-task entry with its approved state' {
            $result = Invoke-StartupCheck
            { Assert-CheckResult $result } | Should -Not -Throw
            $items = @($result.detail.items)

            $items.Count | Should -Be 8
            ($items | Where-Object name -EQ 'Updater').approved_state | Should -Be 'enabled'
            ($items | Where-Object name -EQ 'Fresh').approved_state | Should -Be 'none'
            ($items | Where-Object name -EQ 'Setup').approved_state | Should -Be 'none'
            ($items | Where-Object name -EQ 'Setup').kind | Should -Be 'runonce'
            ($items | Where-Object name -EQ 'Notes.lnk').scope | Should -Be 'user-folder'
            ($items | Where-Object name -EQ 'Old').approved_state | Should -Be 'disabled'
            ($items | Where-Object name -EQ 'Sync').task_path | Should -Be '\Vendor\'
            ($items | Where-Object name -EQ 'Sync').key | Should -BeLike 'task:*'
            ($items | Where-Object name -EQ 'Updater').key | Should -BeLike 'startup:*'
        }

        It 'keeps the raw byte only for an unknown state and the time only for a disabled one' {
            $items = @((Invoke-StartupCheck).detail.items)
            $odd = $items | Where-Object name -EQ 'Odd'
            $odd.approved_state | Should -Be 'unknown'
            $odd.approved_raw_byte | Should -Be 1
            $odd.severity | Should -Be 'UNKNOWN'
            $paused = $items | Where-Object name -EQ 'Paused'
            ([datetime]$paused.disabled_at).ToUniversalTime() | Should -Be $script:DisabledAt
            $paused.approved_raw_byte | Should -BeNullOrEmpty
            ($items | Where-Object name -EQ 'Updater').disabled_at | Should -BeNullOrEmpty
        }

        It 'counts entries that start (enabled or with no approved value), disabled, unknown and tasks' {
            $detail = (Invoke-StartupCheck).detail
            # Start: Updater, Fresh, Setup, Notes.lnk, Sync. Disabled: Paused, Old. Unknown: Odd.
            $detail.enabled_count | Should -Be 5
            $detail.disabled_count | Should -Be 2
            $detail.unknown_state_count | Should -Be 1
            $detail.logon_task_count | Should -Be 2
            $detail.items_count | Should -Be 8
        }

        It 'reads UNKNOWN while an unknown-state item is unmuted' {
            (Invoke-StartupCheck).severity | Should -Be 'UNKNOWN'
        }

        It 'reads UNKNOWN beside listed items when a location cannot be read' {
            Mock Get-RunKeyEntry -ParameterFilter { $Scope -eq 'hklm' -and $Key -eq 'Run' } { New-Read -State 'denied' }
            $key = Get-FindingKey -Kind 'startup' -Identity @('hkcu', 'run', 'Odd')

            $result = Invoke-StartupCheck -MutedKeys @($key)

            $result.severity | Should -Be 'UNKNOWN'
            $result.detail.items_count | Should -Be 8
            $result.detail.unreadable_sources | Should -Be @('hklm Run: denied')
        }

        It 'drops to INFO once that item is muted, keeping it listed' {
            $key = Get-FindingKey -Kind 'startup' -Identity @('hkcu', 'run', 'Odd')

            $result = Invoke-StartupCheck -MutedKeys @($key)

            $result.severity | Should -Be 'INFO'
            $result.detail.muted_count | Should -Be 1
            ($result.detail.items | Where-Object name -EQ 'Odd').muted | Should -BeTrue
        }
    }

    It 'keys a Run and a RunOnce value of the same name apart, so muting one leaves the other' {
        Set-EmptyHost
        Mock Get-RunKeyEntry -ParameterFilter { $Scope -eq 'hkcu' -and $Key -eq 'Run' } {
            New-Read -Entries @(New-Entry -Kind 'run' -Scope 'hkcu' -Name 'Setup')
        }
        Mock Get-RunKeyEntry -ParameterFilter { $Scope -eq 'hkcu' -and $Key -eq 'RunOnce' } {
            New-Read -Entries @(New-Entry -Kind 'runonce' -Scope 'hkcu' -Name 'Setup')
        }
        $runKey = Get-FindingKey -Kind 'startup' -Identity @('hkcu', 'run', 'Setup')

        $items = @((Invoke-StartupCheck -MutedKeys @($runKey)).detail.items)

        $items.Count | Should -Be 2
        ($items | Where-Object kind -EQ 'run').key | Should -Not -Be ($items | Where-Object kind -EQ 'runonce').key
        ($items | Where-Object kind -EQ 'run').muted | Should -BeTrue
        ($items | Where-Object kind -EQ 'runonce').muted | Should -BeFalse
    }

    It 'never reads OK when a location cannot be read' {
        Set-EmptyHost
        Mock Get-RunKeyEntry -ParameterFilter { $Scope -eq 'hklm' -and $Key -eq 'Run' } { New-Read -State 'denied' }

        $result = Invoke-StartupCheck

        $result.severity | Should -Be 'UNKNOWN'
        $result.detail.unreadable_sources | Should -Contain 'hklm Run: denied'
    }

    It 'marks tasks_complete as an admin field without elevation' {
        Set-EmptyHost
        Mock Get-LogonTaskInventory { [pscustomobject]@{ ReadState = 'ok'; Complete = $false; Tasks = @() } }

        $result = Invoke-StartupCheck

        $result.detail.tasks_complete | Should -BeFalse
        $result.detail.admin_fields | Should -Be @('tasks_complete')
        $result.needs_admin | Should -BeFalse
    }

    It 'names no admin field when elevated' {
        Set-EmptyHost
        (Invoke-StartupCheck).detail.PSObject.Properties['admin_fields'] | Should -BeNullOrEmpty
    }
}
