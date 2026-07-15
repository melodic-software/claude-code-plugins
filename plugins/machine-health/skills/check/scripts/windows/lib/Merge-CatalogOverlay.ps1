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
Assert-CatalogEntry afterwards, so a malformed overlay entry is skipped with
a warning rather than blocking the run.
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
        $clone = [pscustomobject]@{}
        foreach ($p in $entry.PSObject.Properties) {
            $clone | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value
        }
        $merged[[string]$entry.id] = $clone
    }

    $overlayChecks = @()
    if ($null -ne $Overlay -and $Overlay.PSObject.Properties['checks']) {
        $overlayChecks = @($Overlay.checks)
    }

    foreach ($patch in $overlayChecks) {
        if ($null -eq $patch -or -not $patch.PSObject.Properties['id'] -or
            [string]::IsNullOrWhiteSpace([string]$patch.id)) {
            Write-Warning 'Merge-CatalogOverlay: overlay entry without id skipped.'
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

    return @($merged.Values)
}
