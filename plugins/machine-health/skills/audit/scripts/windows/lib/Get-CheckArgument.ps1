#Requires -Version 7.4

<#
.SYNOPSIS
Return the per-check argument splat the orchestrator passes when dispatching a
check, or an empty hashtable for checks that take no run-scoped arguments.

.DESCRIPTION
Checks run argument-less by default. Some need run-scoped context the generic
dispatcher must inject:

 - battery: a -ReportPath so powercfg /batteryreport writes somewhere the
   wear/capacity analysis can read it (without a path the check skips capacity).
 - winget-upgrades: a -LogPath so the KEV cache fetch appends its egress line
   to the run log the orchestrator reads into urls_called.
 - any check that declares -MutedKeys: a string[] of the owner's muted
   FindingKeys for that check, since checks never read mutes.json.
 - any check that declares -SampleSeconds: the run's sampling window, offered
   only when the caller passes one. The orchestrator always does; the
   ContainsKey branch serves callers that pass none, so the check script's own
   default stands, as it does on a direct run of the script.

The candidates are filtered against the parameters the check script declares
(read from its metadata, without running it), because splatting a parameter a
script does not declare fails the check. A new check that declares -MutedKeys,
-SampleSeconds, or any later run-scoped argument offered here, receives it with
no per-id edit in this file.

The orchestrator computes the run-scoped paths and muted keys and passes them
in. Neutrally named: cross-OS algorithm.

Get-CheckTimeoutSec gives the dispatch timeout for the splat: the base, or for a
check that samples, its window plus a margin when that is longer.
#>

$script:CheckTimeoutBaseSec = 90
$script:SampleTimeoutMarginSec = 30

function Get-CheckArgument {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)] [string] $CheckId,
        [Parameter(Mandatory = $true)] [string] $ScriptPath,
        [string] $RunLog,
        [string] $BatteryReportPath,
        [AllowNull()] [AllowEmptyCollection()] [string[]] $MutedKeys = @(),
        [int] $SampleSeconds
    )

    $candidates = @{ MutedKeys = [string[]]@($MutedKeys | Where-Object { $null -ne $_ }) }
    if ($PSBoundParameters.ContainsKey('SampleSeconds')) { $candidates['SampleSeconds'] = $SampleSeconds }
    switch ($CheckId) {
        'battery' { $candidates['ReportPath'] = $BatteryReportPath }
        'winget-upgrades' { $candidates['LogPath'] = $RunLog }
    }

    try {
        $declared = (Get-Command -Name $ScriptPath -CommandType ExternalScript -ErrorAction Stop).Parameters.Keys
    } catch {
        Write-Verbose "Get-CheckArgument: cannot read parameters of '$ScriptPath'. $($_.Exception.Message)"
        return @{}
    }

    $splat = @{}
    foreach ($name in $candidates.Keys) {
        if ($name -in $declared) { $splat[$name] = $candidates[$name] }
    }
    return $splat
}

function Get-CheckTimeoutSec {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [hashtable] $Arguments
    )

    if (-not $Arguments.ContainsKey('SampleSeconds')) { return $script:CheckTimeoutBaseSec }
    return [int][math]::Max($script:CheckTimeoutBaseSec, $Arguments['SampleSeconds'] + $script:SampleTimeoutMarginSec)
}
