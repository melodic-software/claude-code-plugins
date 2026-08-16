#Requires -Version 7.4

<#
.SYNOPSIS
Render full inventories from check detail into the report's Appendix section.

.DESCRIPTION
The report template specifies collapsed <details> blocks with full
inventories (driver list, winget upgrade list, event-log top 20, startup
items, scheduled tasks, etc.). This helper walks all check results and
emits one <details> block per inventory-carrying check.

Keeps the main body scannable: anything over 10 rows goes to a <details>
with the count in the summary. Under 10 rows inlines as a table or bullet
list.

Neutrally named. The per-check inventory keys are documented here -- when a
new check adds a renderable inventory, extend this function.

Known inventory keys (by check.id):
    winget-upgrades : detail.upgrades (list of name/id/current/available)
    drivers         : detail.oldest_drivers (list of name/version/date)
    services        : detail.startup_inventory + detail.stopped_auto_services
    event-log-errors: detail.top_sources (provider_and_id/count/first/last)
    windows-update  : detail.recent_hotfixes
#>

function ConvertTo-AppendixMarkdown {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $CheckResults
    )

    if ($CheckResults.Count -eq 0) {
        return '_No data in this run._'
    }

    $sections = [System.Collections.Generic.List[string]]::new()

    foreach ($r in ($CheckResults | Sort-Object id)) {
        if (-not $r.detail) { continue }

        $section = switch ($r.id) {
            'winget-upgrades' { Get-WingetUpgradeAppendix -Detail $r.detail }
            'drivers' { Get-DriverAppendix -Detail $r.detail }
            'services' { Get-ServicesAppendix -Detail $r.detail }
            'event-log-errors' { Get-EventLogAppendix -Detail $r.detail }
            'windows-update' { Get-HotfixAppendix -Detail $r.detail }
            default { $null }
        }
        if ($section) { $sections.Add($section) }
    }

    if ($sections.Count -eq 0) {
        return '_No inventories to surface this run._'
    }
    return ($sections -join "`n`n")
}

function Get-AppendixInventory {
    <#
    .SYNOPSIS
    Items stored under one detail key, or an empty array when the key is absent.
    #>
    param(
        [Parameter(Mandatory)] $Detail,
        [Parameter(Mandatory)] [string] $Key
    )
    if ($Detail.PSObject.Properties[$Key]) { return @($Detail.$Key) }
    return @()
}

function Format-AppendixDetail {
    <#
    .SYNOPSIS
    The one collapsed <details> + markdown-table shape every inventory renders.

    .DESCRIPTION
    Column headers and the row strings are the only thing the per-check
    renderers below actually differ in; the block scaffolding (details/summary,
    header row, alignment divider, blank-line spacing) is identical for all of
    them and lives here so a table that renders in one appendix section renders
    the same way in every other.
    #>
    param(
        [Parameter(Mandatory)] [string] $Summary,
        [Parameter(Mandatory)] [string[]] $Column,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $Row
    )
    $divider = '|' + ('---|' * $Column.Count)
    return @"
<details>
<summary>$Summary</summary>

| $($Column -join ' | ') |
$divider
$($Row -join "`n")

</details>
"@
}

function Get-WingetUpgradeAppendix {
    param([Parameter(Mandatory)] $Detail)
    $items = @(Get-AppendixInventory -Detail $Detail -Key 'upgrades')
    if ($items.Count -eq 0) { return $null }

    $rows = foreach ($u in $items) {
        "| $($u.name) | ``$($u.id)`` | $($u.current_version) | $($u.available_version) |"
    }

    return Format-AppendixDetail -Summary "winget upgrades ($($items.Count))" `
        -Column @('Name', 'Id', 'Installed', 'Available') -Row @($rows)
}

function Get-DriverAppendix {
    param([Parameter(Mandatory)] $Detail)
    $items = @(Get-AppendixInventory -Detail $Detail -Key 'oldest_drivers')
    if ($items.Count -eq 0) { return $null }

    $rows = foreach ($d in $items) {
        $date = $d.driver_date ? ($d.driver_date -split 'T')[0] : 'n/a'
        "| $($d.device_name) | $($d.manufacturer) | $($d.driver_version) | $date |"
    }

    $totalCount = $Detail.PSObject.Properties['total_drivers'] ? $Detail.total_drivers : $items.Count

    return Format-AppendixDetail -Summary "oldest drivers ($($items.Count) of $totalCount)" `
        -Column @('Device', 'Manufacturer', 'Version', 'Date') -Row @($rows)
}

function Get-ServicesAppendix {
    param([Parameter(Mandatory)] $Detail)
    $sections = [System.Collections.Generic.List[string]]::new()

    $stopped = @(Get-AppendixInventory -Detail $Detail -Key 'stopped_auto_services')
    if ($stopped.Count -gt 0) {
        $rows = foreach ($s in $stopped) {
            $delayed = $s.delayed_auto_start ? 'delayed' : 'auto'
            "| ``$($s.name)`` | $($s.display_name) | $delayed |"
        }
        $sections.Add((Format-AppendixDetail -Summary "stopped automatic services ($($stopped.Count))" `
                    -Column @('Name', 'Display', 'StartType') -Row @($rows)))
    }

    $startup = @(Get-AppendixInventory -Detail $Detail -Key 'startup_inventory')
    if ($startup.Count -gt 0) {
        $rows = foreach ($s in $startup) {
            "| $($s.Name) | $($s.User) | $($s.Location) |"
        }
        $sections.Add((Format-AppendixDetail -Summary "startup items ($($startup.Count))" `
                    -Column @('Name', 'User', 'Location') -Row @($rows)))
    }

    if ($sections.Count -eq 0) { return $null }
    return ($sections -join "`n`n")
}

function Get-EventLogAppendix {
    param([Parameter(Mandatory)] $Detail)
    $items = @(Get-AppendixInventory -Detail $Detail -Key 'top_sources')
    if ($items.Count -eq 0) { return $null }

    $rows = foreach ($e in $items) {
        $first = $e.first_seen ? (($e.first_seen -split '\.')[0] -replace 'T', ' ') : ''
        $last = $e.last_seen ? (($e.last_seen -split '\.')[0] -replace 'T', ' ') : ''
        "| ``$($e.provider_and_id)`` | $($e.count) | $first | $last |"
    }

    return Format-AppendixDetail -Summary "event-log top sources ($($items.Count))" `
        -Column @('Provider/Id', 'Count', 'First seen', 'Last seen') -Row @($rows)
}

function Get-HotfixAppendix {
    param([Parameter(Mandatory)] $Detail)
    $items = @(Get-AppendixInventory -Detail $Detail -Key 'recent_hotfixes')
    if ($items.Count -eq 0) { return $null }

    $rows = foreach ($h in $items) {
        $date = $h.installed_on ? ($h.installed_on -split 'T')[0] : ''
        $desc = $h.description ? $h.description : ''
        "| $($h.hotfix_id) | $desc | $date |"
    }

    return Format-AppendixDetail -Summary "recent hotfixes ($($items.Count))" `
        -Column @('KB', 'Description', 'Installed') -Row @($rows)
}
