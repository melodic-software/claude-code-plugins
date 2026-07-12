#Requires -Version 7.4

<#
.SYNOPSIS
Validates that an object conforms to the ApprovalState schema.

.DESCRIPTION
Mirrors Assert-CheckResult and Assert-CatalogEntry for the approvals.json
payload. The authoritative schema is catalog/schemas/approvals.schema.json;
this function pins the shape rules the orchestrator actually relies on
(schema_version, remediations shape, optional migration block).

Returns $true on success; throws on violation. Callers typically catch and
log the message while falling back to default (nothing approved).
#>

function Assert-ApprovalState {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0)] $State,
        [string] $Because
    )

    if ($null -eq $State) { throw 'ApprovalState is null.' }
    $ctx = if ($Because) { " ($Because)" } else { '' }

    $required = @('schema_version', 'remediations')
    foreach ($k in $required) {
        if ($null -eq $State.PSObject.Properties[$k]) {
            throw "ApprovalState missing required field '$k'$ctx."
        }
    }

    if ($State.schema_version -ne '1.0') {
        throw "ApprovalState schema_version '$($State.schema_version)' is not supported (expected '1.0')$ctx."
    }

    if ($null -eq $State.remediations) {
        throw "ApprovalState.remediations is null$ctx."
    }

    foreach ($prop in $State.remediations.PSObject.Properties) {
        $name = $prop.Name
        $value = $prop.Value
        if ($null -eq $value) {
            throw "ApprovalState.remediations['$name'] is null$ctx."
        }
        if ($null -eq $value.PSObject.Properties['approved']) {
            throw "ApprovalState.remediations['$name'] missing required field 'approved'$ctx."
        }
        if ($value.approved -isnot [bool]) {
            throw "ApprovalState.remediations['$name'].approved must be a boolean$ctx."
        }
    }

    if ($State.PSObject.Properties['migration']) {
        $mig = $State.migration
        if ($null -ne $mig -and $mig.PSObject.Properties['migrated_from_todo_md']) {
            if ($mig.migrated_from_todo_md -isnot [bool]) {
                throw 'ApprovalState.migration.migrated_from_todo_md must be a boolean' + $ctx + '.'
            }
        }
    }

    return $true
}
