#Requires -Version 7.4

<#
.SYNOPSIS
Split the enabled checks into the ones due to run this run and the ones a
monthly cadence defers, using each check's last-run from the history tail.

.DESCRIPTION
Cadence lives on the merged catalog entry (`cadence`: weekly | monthly; absent =
weekly). Only the `weekly` RunMode honours a monthly demotion -- `on-demand` and
`first-run` always run every enabled check (the user asked explicitly, or there
is no baseline yet). A monthly check runs on a weekly run only when it has not
run within the monthly interval; a check with no recorded last run (never ran,
or history predates `checks_ran`) is treated as due -- the safe default.

Pure: no logging, no clock reads beyond the injected -Now. Returns
@{ due = <entries[]>; skipped = <records[]> } so the orchestrator can log the
skips and dispatch the due set. Neutrally named: cross-OS algorithm.
#>

. (Join-Path $PSScriptRoot 'Get-CheckLastRun.ps1')

function Get-CheckSelection {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Checks,
        [Parameter(Mandatory = $true)]
        [ValidateSet('weekly', 'on-demand', 'first-run')]
        [string] $RunMode,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $HistoryTail,
        [Parameter(Mandatory = $true)]
        [datetime] $Now
    )

    # A monthly check runs on a weekly run only when at least this many days have
    # passed since it last ran. Biased just under 28 so ordinary weekly-run jitter
    # fires it on the 4th weekly run (~28d) rather than slipping to the 5th.
    $monthlyMinIntervalDays = 27

    $nowOffset = [DateTimeOffset]$Now
    $due = [System.Collections.Generic.List[object]]::new()
    $skipped = [System.Collections.Generic.List[object]]::new()

    foreach ($c in $Checks) {
        $cadence = ($c.PSObject.Properties['cadence'] -and $c.cadence) ? "$($c.cadence)" : 'weekly'

        # on-demand / first-run run everything; weekly-cadence always runs.
        if ($RunMode -ne 'weekly' -or $cadence -ne 'monthly') {
            $due.Add($c)
            continue
        }

        $lastRun = Get-CheckLastRun -CheckId $c.id -HistoryTail $HistoryTail
        if ([string]::IsNullOrWhiteSpace($lastRun)) {
            $due.Add($c)
            continue
        }

        $lastRunOffset = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse($lastRun, [ref]$lastRunOffset)) {
            $due.Add($c)
            continue
        }

        $elapsedDays = ($nowOffset - $lastRunOffset).TotalDays
        if ($elapsedDays -ge $monthlyMinIntervalDays) {
            $due.Add($c)
        } else {
            $skipped.Add([pscustomobject]@{
                    id           = $c.id
                    cadence      = $cadence
                    last_run     = $lastRun
                    elapsed_days = [math]::Round($elapsedDays, 1)
                })
        }
    }

    return @{ due = $due.ToArray(); skipped = $skipped.ToArray() }
}
