#Requires -Version 7.4

<#
.SYNOPSIS
Compute the one-line "delta vs prior run" summary rendered in the report
header. Cross-OS.

.DESCRIPTION
Compares the current severity counts (per category) to the most recent
history entry. Produces strings like:

    "WARN +1 (event-log), INFO -1 (drivers improved), OK unchanged"
    "no prior runs"
    "no change vs 2026-04-22"

Best-effort: history stores severity_counts by category, not by check-id, so
the delta message is category-level rather than per-check. The report's
at-a-glance table is still per-check and carries per-check trend arrows
from Invoke-TrendAnalysis.
#>

function Get-RunDelta {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $HistoryTail,
        [Parameter(Mandatory = $true)] $CurrentSeverityCounts,
        # Checks the current run cadence-deferred. They ran in the prior run (so
        # they inflate its totals) but not this one, which would otherwise read
        # as a spurious severity delta. History is category-grained (no per-check
        # severity), so the deferred checks cannot be subtracted from the prior
        # totals exactly -- disclose the count instead of implying a health change.
        [int] $SkippedCount = 0
    )

    if ($HistoryTail.Count -eq 0) {
        return 'no prior runs'
    }

    # Read-HistoryJsonl returns Get-Content -Tail output which preserves file
    # order (oldest -> newest). The most recent prior run is the LAST element.
    # Using [0] would compare against stale data when there are 2+ entries.
    $prior = $HistoryTail[-1]
    if (-not $prior.PSObject.Properties['severity_counts']) {
        return "no comparable data in prior run $($prior.run_id)"
    }

    $deltas = [System.Collections.Generic.List[string]]::new()
    $severityLevels = @('CRIT', 'WARN', 'INFO', 'UNKNOWN', 'OK')

    foreach ($sev in $severityLevels) {
        $curTotal = 0
        foreach ($cat in $CurrentSeverityCounts.Keys) {
            if ($CurrentSeverityCounts[$cat].ContainsKey($sev)) {
                $curTotal += $CurrentSeverityCounts[$cat][$sev]
            }
        }

        $prevTotal = 0
        foreach ($prop in $prior.severity_counts.PSObject.Properties) {
            $catObj = $prop.Value
            if ($catObj.PSObject.Properties[$sev]) {
                $prevTotal += [int]$catObj.$sev
            }
        }

        $d = $curTotal - $prevTotal
        if ($d -ne 0) {
            $sign = $d -gt 0 ? "+$d" : "$d"
            $deltas.Add("$sev $sign")
        }
    }

    if ($deltas.Count -eq 0) {
        $priorDate = $prior.run_id ? ($prior.run_id -split 'T')[0] : 'prior run'
        $base = "no change vs $priorDate"
    } else {
        $base = ($deltas -join ', ')
    }

    if ($SkippedCount -gt 0) {
        $noun = $SkippedCount -eq 1 ? 'check' : 'checks'
        $base = "$base ($SkippedCount cadence-deferred $noun not compared)"
    }

    return $base
}
