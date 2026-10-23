#Requires -Version 7.4
<#
.SYNOPSIS
Picks the new findings a scheduled audit researches, from latest.json.

.DESCRIPTION
Reads the items under checks[].detail.items[] whose key is in new_finding_keys
(written on a -Scheduled run) and prints one JSON object:

    { "candidates": [{ "key", "kind", "check_id", "title" }], "not_researched": [{ "key", "title" }] }

A candidate is an item of kind startup, task, ext, listener, process or
detection (the FindingKey prefix), a process only at WARN or CRIT, and one per
kind and title, since a listener's port changes between runs. Candidates are
ordered CRIT, WARN, INFO, then any other severity, then by check and item order,
and the first -Max are kept. Every other new key goes to not_researched in
latest.json order. A latest.json without new_finding_keys gives two empty lists.

title is machine-derived text: the caller passes it on as quoted data.

.PARAMETER LatestPath
The run's state/latest.json.

.PARAMETER Max
How many candidates to keep.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $LatestPath,
    [ValidateRange(1, 50)] [int] $Max = 5
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/New-RunSnapshot.ps1')
Set-Alias -Name Get-Field -Value Get-SnapshotField

$kinds = @('startup', 'task', 'ext', 'listener', 'process', 'detection')
$rank = @{ CRIT = 0; WARN = 1; INFO = 2 }

$latest = [System.IO.File]::ReadAllText($LatestPath) | ConvertFrom-Json
$new = [System.Collections.Generic.HashSet[string]]::new([string[]]@(Get-Field $latest 'new_finding_keys' | Where-Object { $_ -is [string] }))

$found = [System.Collections.Generic.List[object]]::new()
foreach ($check in @(Get-Field $latest 'checks')) {
    foreach ($item in @(Get-Field (Get-Field $check 'detail') 'items')) {
        $key = Get-Field $item 'key'
        if ($key -isnot [string] -or -not $new.Contains($key)) { continue }
        $severity = [string](Get-Field $item 'severity')
        $found.Add([pscustomobject]@{
                Order    = $found.Count
                Key      = $key
                Kind     = $key.Split(':')[0]
                CheckId  = [string](Get-Field $check 'id')
                Title    = [string](Get-Field $item 'title')
                Severity = $severity
                Rank     = $rank.ContainsKey($severity) ? $rank[$severity] : 3
            })
    }
}

$seen = [System.Collections.Generic.HashSet[string]]::new()
$picked = [System.Collections.Generic.HashSet[string]]::new()
$candidates = @($found | Sort-Object Rank, Order | Where-Object {
        $_.Kind -in $kinds -and ($_.Kind -ne 'process' -or $_.Severity -in 'WARN', 'CRIT') -and
        $seen.Add("$($_.Kind)|$($_.Title)")
    } | Select-Object -First $Max | ForEach-Object {
        [void]$picked.Add($_.Key)
        [ordered]@{ key = $_.Key; kind = $_.Kind; check_id = $_.CheckId; title = $_.Title }
    })
$rest = @($found | Where-Object { -not $picked.Contains($_.Key) } | ForEach-Object { [ordered]@{ key = $_.Key; title = $_.Title } })

[ordered]@{ candidates = $candidates; not_researched = $rest } | ConvertTo-Json -Depth 4 -Compress
