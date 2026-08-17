#Requires -Version 7.4

<#
.SYNOPSIS
Merge a machine-local catalog overlay into the shipped check catalog.

.DESCRIPTION
The shipped catalog (catalog/checks.jsonc inside the plugin) is read-only at
runtime -- a plugin update replaces it. Machine-specific catalog changes
(disable, deprecate, cadence demotion, custom checks) live in an overlay file
under the state base: catalog/checks.local.jsonc. Merge semantics:

    overlay id matches a shipped id -> overlay properties override that entry's
    overlay id is new               -> entry appended as a custom check

Entries are never deleted by an overlay -- set "enabled": false or
"deprecated": true instead. Callers validate each merged entry with
Assert-CatalogEntry afterwards; a malformed overlay entry is not dispatched,
but the orchestrator synthesizes an UNKNOWN CheckResult so the skip appears
in the report rather than only in the run log. Overlay entries with a missing
or blank id cannot be keyed into the merge map; they are appended unchanged so
New-InvalidCatalogEntryResult can still surface them.
#>

function Merge-CatalogOverlay {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [object[]] $BaseChecks,
        [Parameter(Mandatory = $true)] [AllowNull()] $Overlay
    )

    $merged = [ordered]@{}
    foreach ($entry in $BaseChecks) {
        if ($null -eq $entry -or -not $entry.PSObject.Properties['id']) { continue }
        # Clone each shipped entry so overlay patches never mutate caller state.
        # Shallow by design: nested values stay shared, exactly as the manual
        # property-by-property copy this replaced did.
        $merged[[string]$entry.id] = $entry.PSObject.Copy()
    }

    $overlayChecks = @()
    if ($null -ne $Overlay -and $Overlay.PSObject.Properties['checks']) {
        $overlayChecks = @($Overlay.checks)
    }

    # Id-less overlay rows are retained (not dropped) so the orchestrator's
    # Assert-CatalogEntry loop can emit UNKNOWN findings for them.
    $idLessOverlayEntries = [System.Collections.Generic.List[object]]::new()
    foreach ($patch in $overlayChecks) {
        if ($null -eq $patch) { continue }
        if (-not $patch.PSObject.Properties['id'] -or
            [string]::IsNullOrWhiteSpace([string]$patch.id)) {
            Write-Warning 'Merge-CatalogOverlay: overlay entry without id retained for validation reporting.'
            $idLessOverlayEntries.Add($patch)
            continue
        }
        $id = [string]$patch.id
        if ($merged.Contains($id)) {
            $target = $merged[$id]
            foreach ($p in $patch.PSObject.Properties) {
                if ($p.Name -eq 'id') { continue }
                if ($target.PSObject.Properties[$p.Name]) {
                    $target.($p.Name) = $p.Value
                } else {
                    $target | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value
                }
            }
        } else {
            $merged[$id] = $patch
        }
    }

    return @($merged.Values) + @($idLessOverlayEntries)
}
