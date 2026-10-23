#Requires -Version 7.4

<#
.SYNOPSIS
Write the picks the owner confirmed by number, from a resolved checkup payload.

.DESCRIPTION
Resolves the payload again through Resolve-CheckupPick, the same call that
numbered the list setup showed, so number N is the Nth ResolvedPick. Every
number is checked before anything is written: it must be on the list, not
refused, and of the action it was confirmed for (-Mute numbers mute, -Approve
numbers approve). A number that fails a check throws before anything is
written. Then each pick goes through Set-ApprovalState, mutes first, and its
results are returned; each write is its own, so one that throws (a lock
timeout, an I/O error) can leave the earlier picks written.
#>

. (Join-Path $PSScriptRoot 'Resolve-CheckupPick.ps1')
. (Join-Path $PSScriptRoot 'Set-ApprovalState.ps1')

function Write-CheckupPick {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string] $StateBase,
        [Parameter(Mandatory = $true)] [string] $Payload,
        [int[]] $Mute = @(),
        [int[]] $Approve = @()
    )

    $picks = @(Resolve-CheckupPick -ViewsDir (Join-Path $StateBase 'views') -Payload $Payload)
    $chosen = foreach ($list in @{ Action = 'mute'; N = $Mute }, @{ Action = 'approve'; N = $Approve }) {
        foreach ($n in $list.N) {
            if ($n -lt 1 -or $n -gt $picks.Count) { throw "pick $n is not on the list" }
            $pick = $picks[$n - 1]
            if ($pick.Refused) { throw "pick $n is refused: $($pick.Refused)" }
            if ($pick.Action -cne $list.Action) { throw "pick $n is not on the $($list.Action) list" }
            $pick
        }
    }
    foreach ($pick in $chosen) {
        if ($pick.Action -ceq 'mute') {
            Set-ApprovalState -StateBase $StateBase -Action mute -CheckId $pick.CheckId -FindingKey $pick.FindingKey `
                -Label $pick.Label -Notes $pick.Notes -RunId $pick.RunId
        } else {
            Set-ApprovalState -StateBase $StateBase -Action approve -RemediationId $pick.RemediationId -Notes $pick.Notes -RunId $pick.RunId
        }
    }
}
