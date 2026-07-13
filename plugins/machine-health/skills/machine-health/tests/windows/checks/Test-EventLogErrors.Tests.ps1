#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/checks/Test-EventLogErrors.ps1.

.DESCRIPTION
Pins these fixes:

1. Benign-noise allowlist. DCOM 10016 ("permission denied to local COM
   server") is the canonical harmless event that every Windows install
   logs multiple times per day. Counting it triggered WARN for every
   healthy machine.

2. Allowlist does NOT suppress a DCOM 10016 that coincides with a real
   finding (bugcheck, disk errors). Only the severity contribution is
   removed.

3. Query failure "No events were found" is handled gracefully (not an
   error -- the log simply has nothing matching the filter).

4. The 7-day window is filtered in the Get-WinEvent query (StartTime), not
   by a MaxEvents record cap that could drop in-window errors on a busy host.

5. Severity is filtered on numeric Level (1=Critical, 2=Error), which is
   locale-independent, rather than the localized LevelDisplayName.
#>

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:SkillRoot = Split-Path -Parent $script:TestsRoot
    $script:ScriptPath = Join-Path $script:SkillRoot 'scripts\windows\checks\Test-EventLogErrors.ps1'
    $script:LibRoot = Join-Path $script:SkillRoot 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Assert-CheckResult.ps1')
    Import-Module (Join-Path $script:TestsRoot 'helpers\Mock-Helpers.psm1') -Force

    function Invoke-EventLogAsObject {
        $raw = & $script:ScriptPath
        $json = ($raw | Where-Object { $_ }) -join "`n"
        return $json | ConvertFrom-Json
    }

    function New-NoiseEvent {
        param(
            [string] $ProviderName = 'Microsoft-Windows-DistributedCOM',
            [int] $Id = 10016,
            [datetime] $When = (Get-Date).AddHours(-6)
        )
        New-MockEventLogRecord -ProviderName $ProviderName -Id $Id -TimeCreated $When -LevelDisplayName 'Error'
    }
}

Describe 'Test-EventLogErrors -- healthy baseline' -Tag 'check' {
    BeforeAll {
        Mock Get-WinEvent { @() }
    }

    It 'emits a schema-valid CheckResult' {
        $result = Invoke-EventLogAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.id | Should -Be 'event-log-errors'
    }

    It 'reports OK when no Error/Critical events exist' {
        $result = Invoke-EventLogAsObject
        $result.severity | Should -Be 'OK'
    }
}

Describe 'Test-EventLogErrors -- benign noise allowlist' -Tag 'check' {
    It 'ignores a flood of DistributedCOM 10016 errors' {
        $when = Get-Date
        $events = 1..20 | ForEach-Object {
            New-NoiseEvent -When ($when.AddMinutes(-$_))
        }
        Mock Get-WinEvent { $events }.GetNewClosure()

        $result = Invoke-EventLogAsObject
        # Previous code flagged this WARN because 20 identical entries
        # exceeded the repeat threshold. With DCOM 10016 on the noise
        # allowlist, the whole set is filtered from the severity calc.
        $result.severity | Should -Be 'OK'
        $result.detail.filtered_noise_count | Should -Be 20
    }

    It 'still CRITs on bugcheck even when DCOM 10016 is also present' {
        $bugcheck = New-MockEventLogRecord `
            -ProviderName 'Microsoft-Windows-Kernel-Power' `
            -Id 41 `
            -TimeCreated (Get-Date).AddHours(-12) `
            -LevelDisplayName 'Critical'
        $noise = 1..5 | ForEach-Object { New-NoiseEvent }
        $events = @($bugcheck) + @($noise)
        Mock Get-WinEvent { $events }.GetNewClosure()

        $result = Invoke-EventLogAsObject
        # The allowlist must not mask real findings.
        $result.severity | Should -Be 'CRIT'
        $result.detail.bugcheck_event_count | Should -Be 1
    }
}

Describe 'Test-EventLogErrors -- real findings' -Tag 'check' {
    It 'CRITs on Kernel-Power 41 (unexpected shutdown)' {
        $bugcheck = New-MockEventLogRecord `
            -ProviderName 'Microsoft-Windows-Kernel-Power' `
            -Id 41 `
            -TimeCreated (Get-Date).AddHours(-12) `
            -LevelDisplayName 'Critical'
        Mock Get-WinEvent { @($bugcheck) }.GetNewClosure()

        $result = Invoke-EventLogAsObject
        $result.severity | Should -Be 'CRIT'
    }

    It 'CRITs on disk-source Error events' {
        $disk = New-MockEventLogRecord `
            -ProviderName 'disk' `
            -Id 51 `
            -TimeCreated (Get-Date).AddHours(-12) `
            -LevelDisplayName 'Error'
        Mock Get-WinEvent { @($disk) }.GetNewClosure()

        $result = Invoke-EventLogAsObject
        $result.severity | Should -Be 'CRIT'
    }

    It 'WARNs when a non-noise provider/id repeats more than 5 times' {
        $when = Get-Date
        $events = 1..7 | ForEach-Object {
            New-MockEventLogRecord `
                -ProviderName 'Microsoft-Windows-Spam' `
                -Id 1001 `
                -TimeCreated ($when.AddMinutes(-$_)) `
                -LevelDisplayName 'Error'
        }
        Mock Get-WinEvent { $events }.GetNewClosure()

        $result = Invoke-EventLogAsObject
        $result.severity | Should -Be 'WARN'
    }

    It 'INFOs for a handful of low-repeat errors' {
        $e1 = New-MockEventLogRecord `
            -ProviderName 'Microsoft-Windows-Misc' `
            -Id 1 `
            -TimeCreated (Get-Date).AddHours(-2) `
            -LevelDisplayName 'Error'
        $e2 = New-MockEventLogRecord `
            -ProviderName 'Microsoft-Windows-Other' `
            -Id 2 `
            -TimeCreated (Get-Date).AddHours(-3) `
            -LevelDisplayName 'Error'
        Mock Get-WinEvent { @($e1, $e2) }.GetNewClosure()

        $result = Invoke-EventLogAsObject
        $result.severity | Should -Be 'INFO'
    }
}

Describe 'Test-EventLogErrors -- query scopes window and level in the log query' -Tag 'check' {
    It 'filters the 7-day window (StartTime) and numeric Level 1,2 in the query, not a record cap' {
        Mock Get-WinEvent { @() }

        Invoke-EventLogAsObject | Out-Null

        Should -Invoke Get-WinEvent -Times 1 -Exactly -ParameterFilter {
            # -FilterHashtable binds as Hashtable[]; unwrap the single entry.
            $h = @($FilterHashtable)[0]
            $h['LogName'] -eq 'System' -and
            ($h['Level'] -contains 1) -and ($h['Level'] -contains 2) -and
            $h.ContainsKey('StartTime') -and -not $h.ContainsKey('MaxEvents')
        }
    }
}

Describe 'Test-EventLogErrors -- failure modes' -Tag 'check' {
    It 'treats "No events were found" as OK, not UNKNOWN' {
        Mock Get-WinEvent { throw 'No events were found that match the specified selection criteria.' }

        $result = Invoke-EventLogAsObject
        $result.severity | Should -Be 'OK'
        $result.ran_successfully | Should -BeTrue
    }

    It 'treats a localized no-match error as OK via the error id, not the message' {
        # Healthy non-English host: Get-WinEvent raises NoMatchingEventsFound but
        # the message is localized. Matching only the English text would report
        # UNKNOWN; the FullyQualifiedErrorId check keeps it OK.
        Mock Get-WinEvent {
            $ex = [System.Exception]::new('Es wurden keine Ereignisse gefunden, die den angegebenen Kriterien entsprechen.')
            throw [System.Management.Automation.ErrorRecord]::new(
                $ex,
                'NoMatchingEventsFound,Microsoft.PowerShell.Commands.GetWinEventCommand',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $null)
        }

        $result = Invoke-EventLogAsObject
        $result.severity | Should -Be 'OK'
        $result.ran_successfully | Should -BeTrue
    }

    It 'emits UNKNOWN when Get-WinEvent fails for a non-empty reason' {
        Mock Get-WinEvent { throw 'Event log service is not running' }

        $result = Invoke-EventLogAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.severity | Should -Be 'UNKNOWN'
        $result.ran_successfully | Should -BeFalse
    }
}
