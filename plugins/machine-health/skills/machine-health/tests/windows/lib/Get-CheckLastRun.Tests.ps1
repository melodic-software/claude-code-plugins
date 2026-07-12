#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Get-CheckLastRun.ps1 -- the per-check last-run
lookup shared by cadence selection and trend annotation.
#>

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:LibRoot = Join-Path (Split-Path -Parent $script:TestsRoot) 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Get-CheckLastRun.ps1')

    function New-Entry {
        param([string] $RunId, [string[]] $ChecksRan)
        [pscustomobject]@{ run_id = $RunId; checks_ran = $ChecksRan }
    }
}

Describe 'Get-CheckLastRun' -Tag 'lib' {
    It 'returns null for an empty tail' {
        Get-CheckLastRun -CheckId 'disk-space' -HistoryTail @() | Should -BeNullOrEmpty
    }

    It 'returns null when no entry recorded the check running' {
        $tail = @(New-Entry -RunId '2026-05-01T00:00:00Z' -ChecksRan @('battery'))
        Get-CheckLastRun -CheckId 'disk-space' -HistoryTail $tail | Should -BeNullOrEmpty
    }

    It 'returns the run_id of the newest entry recording the check (tail is oldest -> newest)' {
        $tail = @(
            New-Entry -RunId '2026-05-01T00:00:00Z' -ChecksRan @('disk-space')
            New-Entry -RunId '2026-05-08T00:00:00Z' -ChecksRan @('disk-space', 'battery')
            New-Entry -RunId '2026-05-15T00:00:00Z' -ChecksRan @('battery')
        )
        Get-CheckLastRun -CheckId 'disk-space' -HistoryTail $tail | Should -Be '2026-05-08T00:00:00Z'
    }

    It 'ignores entries missing checks_ran (pre-field history lines)' {
        $tail = @(
            [pscustomobject]@{ run_id = '2026-05-01T00:00:00Z' }
            New-Entry -RunId '2026-05-08T00:00:00Z' -ChecksRan @('disk-space')
        )
        Get-CheckLastRun -CheckId 'disk-space' -HistoryTail $tail | Should -Be '2026-05-08T00:00:00Z'
    }

    It 'normalizes a datetime run_id (ConvertFrom-Json coercion) back to parseable ISO 8601' {
        # ConvertFrom-Json coerces an ISO run_id string to [datetime]; the helper
        # must re-emit ISO, not a locale-specific "MM/dd/yyyy" string that would
        # misparse for cadence math on a non-US-locale host.
        $dt = [datetime]::new(2026, 5, 8, 9, 30, 0, [System.DateTimeKind]::Utc)
        $tail = @([pscustomobject]@{ run_id = $dt; checks_ran = @('disk-space') })
        $result = Get-CheckLastRun -CheckId 'disk-space' -HistoryTail $tail
        { [datetimeoffset]::Parse($result) } | Should -Not -Throw
        ([datetimeoffset]$result).UtcDateTime | Should -Be $dt
    }
}
