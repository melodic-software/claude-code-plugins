#Requires -Version 7.4

<#
.SYNOPSIS
Return the per-check argument splat the orchestrator passes when dispatching a
check, or an empty hashtable for checks that take no run-scoped arguments.

.DESCRIPTION
Checks run argument-less by default. Two need run-scoped context the generic
dispatcher must inject:

 - battery: a -ReportPath so powercfg /batteryreport writes somewhere the
   wear/capacity analysis can read it (without a path the check skips capacity).
 - winget-upgrades: a -LogPath so the KEV cache fetch appends its egress line
   to the run log the orchestrator reads into urls_called.

Pure lookup keyed on the check id; the orchestrator computes the run-scoped
paths and passes them in. Neutrally named: cross-OS algorithm.
#>

function Get-CheckArgument {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)] [string] $CheckId,
        [string] $RunLog,
        [string] $BatteryReportPath
    )

    switch ($CheckId) {
        'battery' { return @{ ReportPath = $BatteryReportPath } }
        'winget-upgrades' { return @{ LogPath = $RunLog } }
        default { return @{} }
    }
}
