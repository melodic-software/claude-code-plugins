#Requires -Version 7.4

<#
.SYNOPSIS
Cap a custom (overlay-registered) check at WARN until history shows it
reporting clean, so a model-authored check cannot open with a CRIT.

.DESCRIPTION
A custom check passes the discovery guide's safety bar (read-only, no new
egress, narrow scope), but nothing tests whether its verdicts are true. The
proof this clamp accepts is behavioral: the check has reported OK or INFO in
at least -RequiredCleanRuns history runs, so it is known to say "fine" when
things are fine. Until then a CRIT is capped at WARN and the note says why.

Clean runs are counted from history's check_severities map, which records
each successfully-run check's final severity. Runs recorded before that map
existed carry no evidence and count as zero. Runs need not be consecutive: a
real problem that persists would otherwise keep the check clamped forever.

Runs after trend analysis and correlation, so it caps every upgrade path.
Shipped checks are never touched. Neutrally named: cross-OS algorithm.
#>

function Invoke-CustomCheckClamp {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [object[]] $CheckResults,
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [string[]] $CustomIds,
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [object[]] $HistoryTail,
        [int] $RequiredCleanRuns = 3
    )

    if ($CustomIds.Count -eq 0) { return $CheckResults }

    foreach ($r in $CheckResults) {
        if ($CustomIds -notcontains $r.id -or $r.severity -ne 'CRIT') { continue }

        $cleanRuns = Get-CleanRunCount -CheckId $r.id -HistoryTail $HistoryTail
        if ($cleanRuns -ge $RequiredCleanRuns) { continue }

        $r.severity = 'WARN'
        $note = ("custom check clamp: CRIT capped at WARN until it reports clean in " +
            "$RequiredCleanRuns runs ($cleanRuns so far)")
        $r.notes = $r.notes ? "$($r.notes); $note" : $note
        # A trend upgrade the clamp undid leaves no net adjustment to report.
        if ($r.PSObject.Properties['trend'] -and $r.trend -and $r.trend.adjusted_from -eq 'WARN') {
            $r.trend.adjusted_from = $null
        }
    }

    return $CheckResults
}

function Get-CleanRunCount {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)] [string] $CheckId,
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [object[]] $HistoryTail
    )

    $count = 0
    foreach ($h in $HistoryTail) {
        if (-not $h.PSObject.Properties['checks_ran'] -or @($h.checks_ran) -notcontains $CheckId) { continue }
        if (-not $h.PSObject.Properties['check_severities'] -or $null -eq $h.check_severities) { continue }
        $entry = $h.check_severities.PSObject.Properties[$CheckId]
        if ($entry -and $entry.Value -in @('OK', 'INFO')) { $count++ }
    }
    return $count
}
