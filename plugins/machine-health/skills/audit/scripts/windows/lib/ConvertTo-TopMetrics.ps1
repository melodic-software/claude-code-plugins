#Requires -Version 7.4

<#
.SYNOPSIS
Flattens each check result's scalar detail properties into a single dict keyed
"<checkId>.<detailKey>" for append to history.jsonl's top_metrics field.

.DESCRIPTION
Trend queries read the last N history entries and look up metrics by
"<checkId>.*" pattern match. Without this denormalization they would have to
rehydrate every run's full JSON. Only scalars are captured; nested objects
and arrays are omitted so history lines stay compact.

Handles both hashtable (direct-call) and PSCustomObject (post-JSON round-
trip) detail shapes -- the orchestrator receives PSCustomObject after
Start-Job serialization, so the loop must not assume hashtable semantics.

Neutrally named: cross-OS algorithm, no Windows-specific logic.
#>

function ConvertTo-TopMetric {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $CheckResults
    )

    $out = [ordered]@{}

    foreach ($r in $CheckResults) {
        if (-not $r -or -not $r.PSObject.Properties['detail']) { continue }
        if ($null -eq $r.detail) { continue }

        foreach ($p in (Get-DetailPair -Detail $r.detail)) {
            $value = $p.Value
            $isScalar = $value -is [bool] -or
            $value -is [string] -or
            $value -is [int] -or
            $value -is [long] -or
            $value -is [double] -or
            $value -is [float] -or
            $value -is [decimal] -or
            $value -is [byte] -or
            $value -is [short]

            if ($isScalar) { $out["$($r.id).$($p.Key)"] = $value }
        }
    }

    return $out
}

function Get-DetailPair {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)] $Detail
    )

    $pairs = [System.Collections.Generic.List[pscustomobject]]::new()

    if ($Detail -is [System.Collections.IDictionary]) {
        foreach ($key in $Detail.Keys) {
            $pairs.Add([pscustomobject]@{ Key = "$key"; Value = $Detail[$key] })
        }
    } else {
        foreach ($prop in $Detail.PSObject.Properties) {
            $pairs.Add([pscustomobject]@{ Key = $prop.Name; Value = $prop.Value })
        }
    }

    return $pairs.ToArray()
}
