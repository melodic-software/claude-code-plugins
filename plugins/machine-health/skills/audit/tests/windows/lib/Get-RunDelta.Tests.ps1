#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-RunDelta.ps1'

    # Builds the JSON-round-tripped history shape Get-RunDelta reads: every
    # category map is a pscustomobject, because the function walks
    # severity_counts via PSObject.Properties.
    function New-PriorRun {
        param([string] $RunId, [hashtable] $SeverityCountsByCategory)
        $byCategory = [ordered]@{}
        foreach ($category in $SeverityCountsByCategory.Keys) {
            $byCategory[$category] = [pscustomobject]$SeverityCountsByCategory[$category]
        }
        [pscustomobject]@{ run_id = $RunId; severity_counts = [pscustomobject]$byCategory }
    }
}

Describe 'Get-RunDelta' -Tag 'lib' {
    It 'says "no prior runs" when history is empty' {
        $current = @{ storage = @{ OK = 1; WARN = 0 } }
        Get-RunDelta -HistoryTail @() -CurrentSeverityCounts $current | Should -Be 'no prior runs'
    }

    It 'reports "no change" when totals match' {
        $prior = New-PriorRun -RunId '2026-04-22T00:00:00-04:00' -SeverityCountsByCategory @{
            storage = @{ OK = 1; WARN = 0; INFO = 0; CRIT = 0; UNKNOWN = 0 }
        }
        $current = @{ storage = @{ OK = 1; WARN = 0; INFO = 0; CRIT = 0; UNKNOWN = 0 } }
        Get-RunDelta -HistoryTail @($prior) -CurrentSeverityCounts $current | Should -Match 'no change'
    }

    It 'reports deltas when totals change' {
        $prior = New-PriorRun -RunId '2026-04-22T00:00:00-04:00' -SeverityCountsByCategory @{
            storage  = @{ OK = 1; WARN = 0; INFO = 0; CRIT = 0; UNKNOWN = 0 }
            security = @{ OK = 1; WARN = 0; INFO = 0; CRIT = 0; UNKNOWN = 0 }
        }
        $current = @{
            storage  = @{ OK = 0; WARN = 1; INFO = 0; CRIT = 0; UNKNOWN = 0 }
            security = @{ OK = 1; WARN = 0; INFO = 0; CRIT = 0; UNKNOWN = 0 }
        }
        $delta = Get-RunDelta -HistoryTail @($prior) -CurrentSeverityCounts $current
        $delta | Should -Match 'WARN \+1'
        $delta | Should -Match 'OK -1'
    }

    It 'uses the most recent (last) history entry as baseline, not the oldest (regression)' {
        # Read-HistoryJsonl returns oldest -> newest via Get-Content -Tail.
        # With 2+ entries, the baseline must be the LAST element, not [0].
        # Here: oldest had WARN=2, newest had WARN=0; current has WARN=0.
        # Correct: no change (vs newest). Wrong: WARN -2 (vs oldest).
        $oldest = New-PriorRun -RunId '2026-04-20T00:00:00-04:00' -SeverityCountsByCategory @{
            storage = @{ OK = 0; WARN = 2; INFO = 0; CRIT = 0; UNKNOWN = 0 }
        }
        $newest = New-PriorRun -RunId '2026-04-23T00:00:00-04:00' -SeverityCountsByCategory @{
            storage = @{ OK = 2; WARN = 0; INFO = 0; CRIT = 0; UNKNOWN = 0 }
        }
        $current = @{ storage = @{ OK = 2; WARN = 0; INFO = 0; CRIT = 0; UNKNOWN = 0 } }
        $delta = Get-RunDelta -HistoryTail @($oldest, $newest) -CurrentSeverityCounts $current
        $delta | Should -Match 'no change vs 2026-04-23'
    }

    It 'discloses cadence-deferred checks so a skip-driven total drop is not read as a health delta' {
        # Prior run counted a check (OK) that this weekly run cadence-deferred, so
        # the OK total drops purely from the skip -- disclose it rather than imply
        # health changed.
        $prior = New-PriorRun -RunId '2026-04-22T00:00:00-04:00' -SeverityCountsByCategory @{
            security = @{ OK = 2; WARN = 0; INFO = 0; CRIT = 0; UNKNOWN = 0 }
        }
        $current = @{ security = @{ OK = 1; WARN = 0; INFO = 0; CRIT = 0; UNKNOWN = 0 } }
        $delta = Get-RunDelta -HistoryTail @($prior) -CurrentSeverityCounts $current -SkippedCount 1
        $delta | Should -Match 'OK -1'
        $delta | Should -Match '1 cadence-deferred check not compared'
    }

    It 'adds no disclosure when nothing was cadence-deferred' {
        $prior = New-PriorRun -RunId '2026-04-22T00:00:00-04:00' -SeverityCountsByCategory @{
            storage = @{ OK = 1; WARN = 0; INFO = 0; CRIT = 0; UNKNOWN = 0 }
        }
        $current = @{ storage = @{ OK = 1; WARN = 0; INFO = 0; CRIT = 0; UNKNOWN = 0 } }
        $delta = Get-RunDelta -HistoryTail @($prior) -CurrentSeverityCounts $current -SkippedCount 0
        $delta | Should -Not -Match 'cadence-deferred'
    }
}
