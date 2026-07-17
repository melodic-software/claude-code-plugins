#Requires -Version 7.4

<#
.SYNOPSIS
Minimal discovery pass: inventory host dimensions, compare against the
catalog, and propose up to 3 new check candidates. Shared framework; the
Windows-specific probes live in Get-WindowsDiscoveryProbes.ps1.

.DESCRIPTION
Per references/shared/discovery-guide.md, discovery runs every invocation
and surfaces proposals in the report. v1 is probe-and-report only -- no
catalog mutations, no TODO.md writes. Catalog mutation is a v2 feature once
probes and classifications are proven stable.

For each probed dimension:
 - If a related check exists in the catalog, emit nothing (already covered).
 - Otherwise, emit a proposal record with { dimension, detected, suggested_check_id, rationale, straightforward }.

The orchestrator renders these in the report's "Newly discovered checks"
section. Capped at 3 proposals per run to avoid floods.

Neutrally named. OS-specific probes come from Get-WindowsDiscoveryProbes.ps1
(dot-sourced separately).
#>

function Invoke-Discovery {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Catalog,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $ProbeResults,
        [int] $MaxProposals = 3
    )

    $existingIds = @{}
    foreach ($entry in $Catalog) {
        if ($entry.PSObject.Properties['id']) {
            $existingIds[$entry.id] = $true
        }
    }

    $proposals = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($probe in $ProbeResults) {
        if ($proposals.Count -ge $MaxProposals) { break }
        if (-not $probe.PSObject.Properties['detected']) { continue }
        if (-not $probe.detected) { continue }
        if (-not $probe.PSObject.Properties['suggested_check_id']) { continue }
        if ($existingIds.ContainsKey($probe.suggested_check_id)) { continue }

        $proposals.Add([pscustomobject]@{
                dimension           = $probe.dimension
                detected            = $true
                suggested_check_id  = $probe.suggested_check_id
                rationale           = $probe.rationale
                straightforward     = [bool]$probe.straightforward
            })
    }

    return $proposals.ToArray()
}

function Get-DiscoveryMarkdown {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Proposals
    )

    if ($Proposals.Count -eq 0) {
        return '_No new checks proposed this run._'
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($p in $Proposals) {
        $class = if ($p.straightforward) { 'straightforward' } else { 'needs approval' }
        $lines.Add(
            "- **$($p.dimension)** ($class) - proposed check id: " +
            "``$($p.suggested_check_id)``. $($p.rationale)")
    }
    return ($lines -join "`n")
}
