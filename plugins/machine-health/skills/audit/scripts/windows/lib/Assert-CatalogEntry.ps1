#Requires -Version 7.4

<#
.SYNOPSIS
Validates that an object conforms to the CheckCatalog entry schema.

.DESCRIPTION
Mirrors Assert-CheckResult but for catalog/checks.jsonc entries. The
authoritative schema lives in catalog/schemas/checks.schema.json; this
function covers the fields and rules the orchestrator relies on.

Returns $true on success; throws on violation with a message that names the
offending entry by id (or a stable index when id is missing/invalid).
Callers typically wrap in try/catch and skip invalid entries with a warning
so a single typo does not prevent the orchestrator from running the rest
of the catalog.
#>

function Assert-CatalogEntry {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0)] $Entry,
        [string] $Because
    )

    if ($null -eq $Entry) {
        throw 'CatalogEntry is null.'
    }

    $ctx = if ($Because) { " ($Because)" } else { '' }

    $requiredKeys = @(
        'added_on', 'category', 'crash_count', 'deprecated', 'enabled',
        'id', 'identical_streak', 'needs_admin', 'os', 'script',
        'severity_rules'
    )
    $actualKeys = @($Entry.PSObject.Properties.Name)
    foreach ($k in $requiredKeys) {
        if ($k -notin $actualKeys) {
            $label = if ($Entry.PSObject.Properties['id']) { $Entry.id } else { '<no id>' }
            throw "CatalogEntry '$label' missing required field '$k'$ctx."
        }
    }

    if ($Entry.id -cnotmatch '^[a-z][a-z0-9-]*[a-z0-9]$') {
        throw "CatalogEntry.id '$($Entry.id)' is not valid kebab-case$ctx."
    }

    $validCategories = @(
        'drivers', 'network', 'power', 'reliability',
        'security', 'services', 'storage', 'updates'
    )
    if ($Entry.category -notin $validCategories) {
        throw "CatalogEntry '$($Entry.id)' category '$($Entry.category)' not in allowed set$ctx."
    }

    if (-not @($Entry.os) -or @($Entry.os).Count -eq 0) {
        throw "CatalogEntry '$($Entry.id)' os list is empty$ctx."
    }
    foreach ($o in $Entry.os) {
        if ($o -notin @('linux', 'macos', 'windows')) {
            throw "CatalogEntry '$($Entry.id)' os '$o' not in allowed set$ctx."
        }
    }

    if ($Entry.script -notmatch '^scripts/(linux|macos|windows)/checks/[A-Za-z0-9_-]+\.ps1$') {
        $msg = "CatalogEntry '$($Entry.id)' script path '$($Entry.script)'" +
        " is not scripts/<os>/checks/Name.ps1$ctx."
        throw $msg
    }

    if ($Entry.added_on -notmatch '^\d{4}-\d{2}-\d{2}$') {
        throw "CatalogEntry '$($Entry.id)' added_on '$($Entry.added_on)' is not ISO 8601 date (yyyy-MM-dd)$ctx."
    }

    if ($Entry.crash_count -lt 0) {
        throw "CatalogEntry '$($Entry.id)' crash_count is negative$ctx."
    }
    if ($Entry.identical_streak -lt 0) {
        throw "CatalogEntry '$($Entry.id)' identical_streak is negative$ctx."
    }

    if ($Entry.deprecated) {
        if ($null -eq $Entry.PSObject.Properties['deprecation_reason'] -or
            [string]::IsNullOrWhiteSpace($Entry.deprecation_reason)) {
            throw "CatalogEntry '$($Entry.id)' is deprecated but has no deprecation_reason$ctx."
        }
    }

    if ($Entry.PSObject.Properties['cadence'] -and $Entry.cadence -and
        $Entry.cadence -notin @('weekly', 'monthly')) {
        throw "CatalogEntry '$($Entry.id)' cadence '$($Entry.cadence)' not in allowed set (weekly, monthly)$ctx."
    }

    return $true
}
