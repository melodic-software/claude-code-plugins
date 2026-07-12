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

function Get-WingetUpgradeAppendix {
    param([Parameter(Mandatory)] $Detail)
    $items = if ($Detail.PSObject.Properties['upgrades']) { @($Detail.upgrades) } else { @() }
    if ($items.Count -eq 0) { return $null }

    $rows = foreach ($u in $items) {
        "| $($u.name) | ``$($u.id)`` | $($u.current_version) | $($u.available_version) |"
    }

    @"
<details>
<summary>winget upgrades ($($items.Count))</summary>

| Name | Id | Installed | Available |
|---|---|---|---|
$($rows -join "`n")

</details>
"@
}

function Get-DriverAppendix {
    param([Parameter(Mandatory)] $Detail)
    $items = if ($Detail.PSObject.Properties['oldest_drivers']) { @($Detail.oldest_drivers) } else { @() }
    if ($items.Count -eq 0) { return $null }

    $rows = foreach ($d in $items) {
        $date = $d.driver_date ? ($d.driver_date -split 'T')[0] : 'n/a'
        "| $($d.device_name) | $($d.manufacturer) | $($d.driver_version) | $date |"
    }

    $totalCount = $Detail.PSObject.Properties['total_drivers'] ? $Detail.total_drivers : $items.Count

    @"
<details>
<summary>oldest drivers ($($items.Count) of $totalCount)</summary>

| Device | Manufacturer | Version | Date |
|---|---|---|---|
$($rows -join "`n")

</details>
"@
}

function Get-ServicesAppendix {
    param([Parameter(Mandatory)] $Detail)
    $sections = [System.Collections.Generic.List[string]]::new()

    if ($Detail.PSObject.Properties['stopped_auto_services']) {
        $items = @($Detail.stopped_auto_services)
        if ($items.Count -gt 0) {
            $rows = foreach ($s in $items) {
                $delayed = $s.delayed_auto_start ? 'delayed' : 'auto'
                "| ``$($s.name)`` | $($s.display_name) | $delayed |"
            }
            $sections.Add(@"
<details>
<summary>stopped automatic services ($($items.Count))</summary>

| Name | Display | StartType |
|---|---|---|
$($rows -join "`n")

</details>
"@)
        }
    }

    if ($Detail.PSObject.Properties['startup_inventory']) {
        $items = @($Detail.startup_inventory)
        if ($items.Count -gt 0) {
            $rows = foreach ($s in $items) {
                "| $($s.Name) | $($s.User) | $($s.Location) |"
            }
            $sections.Add(@"
<details>
<summary>startup items ($($items.Count))</summary>

| Name | User | Location |
|---|---|---|
$($rows -join "`n")

</details>
"@)
        }
    }

    if ($sections.Count -eq 0) { return $null }
    return ($sections -join "`n`n")
}

function Get-EventLogAppendix {
    param([Parameter(Mandatory)] $Detail)
    $items = if ($Detail.PSObject.Properties['top_sources']) { @($Detail.top_sources) } else { @() }
    if ($items.Count -eq 0) { return $null }

    $rows = foreach ($e in $items) {
        $first = $e.first_seen ? (($e.first_seen -split '\.')[0] -replace 'T', ' ') : ''
        $last = $e.last_seen ? (($e.last_seen -split '\.')[0] -replace 'T', ' ') : ''
        "| ``$($e.provider_and_id)`` | $($e.count) | $first | $last |"
    }

    @"
<details>
<summary>event-log top sources ($($items.Count))</summary>

| Provider/Id | Count | First seen | Last seen |
|---|---|---|---|
$($rows -join "`n")

</details>
"@
}

function Get-HotfixAppendix {
    param([Parameter(Mandatory)] $Detail)
    $items = if ($Detail.PSObject.Properties['recent_hotfixes']) { @($Detail.recent_hotfixes) } else { @() }
    if ($items.Count -eq 0) { return $null }

    $rows = foreach ($h in $items) {
        $date = $h.installed_on ? ($h.installed_on -split 'T')[0] : ''
        $desc = $h.description ? $h.description : ''
        "| $($h.hotfix_id) | $desc | $date |"
    }

    @"
<details>
<summary>recent hotfixes ($($items.Count))</summary>

| KB | Description | Installed |
|---|---|---|
$($rows -join "`n")

</details>
"@
}
