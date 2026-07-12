#Requires -Version 7.4

<#
.SYNOPSIS
Return the run_id (ISO timestamp) of the most recent history entry in which a
given check actually ran, or $null when the tail records no such run.

.DESCRIPTION
history.jsonl lines carry a `checks_ran` array -- the ids of the checks the
orchestrator dispatched that run (cadence-skipped and script-missing checks are
absent). This is the authoritative per-check "when did it last run" signal, used
by two callers:

 - cadence-aware selection (Get-CheckSelection): a monthly check is due only when
   it has not run within the monthly interval.
 - trend annotation (Invoke-TrendAnalysis): the `trend.last_run` field.

History lines written before `checks_ran` existed simply lack the field; those
entries are treated as "did not record this check," so the check is considered
never-run from the tail's perspective (callers then run it -- the safe default).

HistoryTail is ordered oldest -> newest (Get-Content -Tail order), so the scan
walks newest-first and returns the first match.

Neutrally named: cross-OS algorithm, no Windows-specific logic.
#>

function Get-CheckLastRun {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)] [string] $CheckId,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $HistoryTail
    )

    for ($i = $HistoryTail.Count - 1; $i -ge 0; $i--) {
        $entry = $HistoryTail[$i]
        if ($null -eq $entry -or -not $entry.PSObject.Properties['checks_ran']) { continue }
        if (@($entry.checks_ran) -contains $CheckId) {
            if ($entry.PSObject.Properties['run_id'] -and $entry.run_id) {
                # ConvertFrom-Json coerces the ISO run_id string to [datetime];
                # normalize back to ISO 8601 so downstream parsing is locale-
                # independent ("MM/dd/yyyy" round-trips would misparse abroad).
                $runId = $entry.run_id
                if ($runId -is [datetime]) { return ([datetimeoffset]$runId).ToString('o') }
                if ($runId -is [datetimeoffset]) { return $runId.ToString('o') }
                return "$runId"
            }
        }
    }
    return $null
}
