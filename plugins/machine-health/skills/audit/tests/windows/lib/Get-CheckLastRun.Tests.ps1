#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-CheckLastRun.ps1'

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

    It 'finds a check whose last run is deeper than 8 entries back (justifies the deep cadence tail)' {
        $tail = @(
            New-Entry -RunId '2026-05-01T00:00:00Z' -ChecksRan @('cert-expiry')
        )
        1..14 | ForEach-Object {
            $tail += New-Entry -RunId ('2026-05-{0:d2}T00:00:00Z' -f ($_ + 1)) -ChecksRan @('disk-space')
        }
        Get-CheckLastRun -CheckId 'cert-expiry' -HistoryTail $tail | Should -Be '2026-05-01T00:00:00Z'
    }

    It 'normalizes a datetime run_id (ConvertFrom-Json coercion) back to parseable ISO 8601' {
        $dt = [datetime]::new(2026, 5, 8, 9, 30, 0, [System.DateTimeKind]::Utc)
        $tail = @([pscustomobject]@{ run_id = $dt; checks_ran = @('disk-space') })
        $result = Get-CheckLastRun -CheckId 'disk-space' -HistoryTail $tail
        { [datetimeoffset]::Parse($result) } | Should -Not -Throw
        ([datetimeoffset]$result).UtcDateTime | Should -Be $dt
    }
}
