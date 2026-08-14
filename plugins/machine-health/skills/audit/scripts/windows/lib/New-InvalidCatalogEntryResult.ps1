#Requires -Version 7.4

<#
.SYNOPSIS
Synthesizes a CheckResult for a catalog entry that failed Assert-CatalogEntry.

.DESCRIPTION
When the orchestrator continues past one bad catalog entry (so a typo does not
take down the whole run), the skip must still be visible in the report,
latest.json, and severity_counts — not only in the run log. This helper builds
a schema-valid UNKNOWN result for that path:

- id: the entry's id when present and kebab-valid; otherwise catalog-entry-<Index>
- category: the entry's declared category when it is in the enum; otherwise
  reliability (the audit's own mechanism failed)
- severity UNKNOWN, ran_successfully false, error = the Assert-CatalogEntry message
- summary: "catalog entry invalid, check did not run: <first line of error>"
#>

. (Join-Path $PSScriptRoot 'Write-HealthResult.ps1')

function New-InvalidCatalogEntryResult {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $false)] $Entry,
        [Parameter(Mandatory = $true)] [int] $Index,
        [Parameter(Mandatory = $true)] [string] $ErrorMessage,
        [ValidateSet('windows', 'macos', 'linux')] [string] $Os = 'windows'
    )

    $validCategories = @(
        'config', 'drivers', 'network', 'power', 'reliability',
        'security', 'services', 'storage', 'updates'
    )

    $id = "catalog-entry-$Index"
    if ($null -ne $Entry -and $null -ne $Entry.PSObject.Properties['id']) {
        $candidateId = [string]$Entry.id
        if ($candidateId -cmatch '^[a-z][a-z0-9-]*[a-z0-9]$') {
            $id = $candidateId
        }
    }

    $category = 'reliability'
    if ($null -ne $Entry -and $null -ne $Entry.PSObject.Properties['category']) {
        $candidateCategory = [string]$Entry.category
        if ($candidateCategory -in $validCategories) {
            $category = $candidateCategory
        }
    }

    $needsAdmin = $false
    if ($null -ne $Entry -and $null -ne $Entry.PSObject.Properties['needs_admin'] -and
        $Entry.needs_admin -is [bool]) {
        $needsAdmin = $Entry.needs_admin
    }

    $firstLine = (($ErrorMessage -split '\r?\n') | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($firstLine)) {
        $firstLine = 'Assert-CatalogEntry failed'
    }
    $summary = "catalog entry invalid, check did not run: $firstLine"
    if ($summary.Length -gt 240) {
        $summary = $summary.Substring(0, 237) + '...'
    }

    return New-HealthResult `
        -Id $id `
        -Category $category `
        -Os $Os `
        -Severity 'UNKNOWN' `
        -Summary $summary `
        -NeedsAdmin $needsAdmin `
        -RanSuccessfully $false `
        -ErrorMessage $ErrorMessage
}
