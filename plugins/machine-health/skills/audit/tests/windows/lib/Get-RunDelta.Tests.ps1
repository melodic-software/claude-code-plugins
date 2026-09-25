#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-RunDelta.ps1'

    # Builds the JSON-round-tripped history shape: category maps are pscustomobjects,
    # because Get-RunDelta walks severity_counts via PSObject.Properties.
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
        # The baseline must be the LAST (newest) entry: oldest WARN=2, newest WARN=0, current
        # WARN=0 reads no change; comparing to [0] would read WARN -2.
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
        # The OK total drops only because this weekly run cadence-deferred a check; disclose
        # the skip rather than imply health changed.
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
