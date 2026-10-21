#Requires -Version 7.4

<#
.SYNOPSIS
Returns the ordered labels of the catalog checks that run without elevation,
for the pre-run banner's "Covered non-elevated" list.

.DESCRIPTION
The caller passes the run set (Windows, enabled, not deprecated entries), taken
before cadence selection; this keeps the entries with needs_admin: false, so the
banner cannot drift from the catalog. Admin-gated fields of those checks are
listed separately by Get-ElevationMatrix.

Neutrally named: cross-OS filter over catalog entries.
#>

. (Join-Path $PSScriptRoot 'Format-CheckLabel.ps1')

function Get-NonElevatedCoverage {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Catalog,
        [AllowEmptyCollection()]
        [string[]] $CustomIds = @()
    )

    return @($Catalog |
            Where-Object { $_.needs_admin -eq $false } |
            ForEach-Object { Format-CheckLabel -Id ([string]$_.id) -CustomIds $CustomIds })
}
