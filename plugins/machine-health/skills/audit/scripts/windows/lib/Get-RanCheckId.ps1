#Requires -Version 7.4

<#
.SYNOPSIS
Ids of the checks whose final result ran successfully, for history.jsonl
checks_ran.

.DESCRIPTION
checks_ran is the last-run signal cadence selection and trend annotation read.
A result counts when ran_successfully is true and its id is a dispatched check
or one an elevated pass imported. A failed result (a timeout, no output,
invalid JSON) is no cadence signal: counting it would defer a monthly check
about 27 days instead of retrying it next run. Notes such as elevated-pass or
state-location are not checks and never count. Each id appears once, in result
order.
#>

function Get-RanCheckId {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [AllowEmptyCollection()] [object[]] $CheckResults = @(),
        [AllowEmptyCollection()] [string[]] $DispatchedIds = @(),
        [AllowEmptyCollection()] [string[]] $ImportedIds = @()
    )

    $ran = [System.Collections.Generic.List[string]]::new()
    foreach ($r in $CheckResults) {
        $id = [string]$r.id
        if ($r.ran_successfully -and ($id -cin $DispatchedIds -or $id -cin $ImportedIds) -and -not $ran.Contains($id)) {
            $ran.Add($id)
        }
    }
    return [string[]]$ran.ToArray()
}
