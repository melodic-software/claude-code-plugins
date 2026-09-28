#Requires -Version 7.4

<#
.SYNOPSIS
Render one check result's detail as the compact key/value table each finding
block carries (reference/shared/report-template.md, the detail slot).

.DESCRIPTION
The finding block is where a reader decides whether to trust a WARN or CRIT,
so the evidence has to be in the report, not only in latest.json. Scalars
render first so counts and markers survive truncation; collections render as
a count plus a short preview, and full inventories stay in the appendix
(ConvertTo-AppendixMarkdown). Past -MaxRows the table stops and names how
many fields remain in latest.json.

Neutrally named: cross-OS algorithm, no Windows-specific logic.
#>

function Format-MarkdownCell {
    <#
    .SYNOPSIS
    One value made safe for a markdown table cell:     pipes escaped, line breaks
    collapsed, long text cut to -MaxLength with a trailing "...".
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()] $Value,
        [int] $MaxLength = 120
    )
    if ($null -eq $Value) { return '' }
    $text = if ($Value -is [datetime]) { $Value.ToString('o') } else { "$Value" }
    $text = ($text -replace '\s*[\r\n]+\s*', ' ').Trim()
    if ($text.Length -gt $MaxLength) { $text = $text.Substring(0, $MaxLength - 3) + '...' }
    return $text.Replace('|', '\|')
}

function ConvertTo-DetailMarkdown {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()] $Detail,
        [int] $MaxRows = 10
    )

    if ($null -eq $Detail) { return $null }

    $pairs = [System.Collections.Generic.List[object]]::new()
    if ($Detail -is [System.Collections.IDictionary]) {
        foreach ($key in $Detail.Keys) { $pairs.Add([pscustomobject]@{ Key = "$key"; Value = $Detail[$key] }) }
    } else {
        foreach ($prop in $Detail.PSObject.Properties) {
            $pairs.Add([pscustomobject]@{ Key = $prop.Name; Value = $prop.Value })
        }
    }

    $scalarRows = [System.Collections.Generic.List[string]]::new()
    $collectionRows = [System.Collections.Generic.List[string]]::new()
    foreach ($p in $pairs) {
        $value = $p.Value
        if ($null -eq $value) { continue }
        $keyCell = '`' + $p.Key + '`'
        if ($value -is [string] -or $value -is [ValueType]) {
            $scalarRows.Add("| $keyCell | $(Format-MarkdownCell -Value $value) |")
            continue
        }
        if ($value -is [System.Collections.IDictionary] -or $value -is [System.Management.Automation.PSCustomObject]) {
            $names = if ($value -is [System.Collections.IDictionary]) { @($value.Keys) } else { @($value.PSObject.Properties.Name) }
            $collectionRows.Add("| $keyCell | $(Format-MarkdownCell -Value ('{' + ($names -join ', ') + '}')) |")
            continue
        }
        $items = @($value)
        if ($items.Count -eq 0) { continue }
        $scalarItems = @($items | Where-Object { $_ -is [string] -or $_ -is [ValueType] })
        $preview = if ($scalarItems.Count -eq $items.Count) {
            $head = ($items | Select-Object -First 3) -join ', '
            $more = $items.Count -gt 3 ? ', ...' : ''
            ": $head$more"
        } else { '' }
        $noun = $items.Count -eq 1 ? 'item' : 'items'
        $collectionRows.Add("| $keyCell | $(Format-MarkdownCell -Value "$($items.Count) $noun$preview") |")
    }

    $rows = @($scalarRows) + @($collectionRows)
    if ($rows.Count -eq 0) { return $null }

    $shown = @($rows | Select-Object -First $MaxRows)
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('| Detail | Value |')
    $lines.Add('|---|---|')
    foreach ($row in $shown) { $lines.Add($row) }
    if ($rows.Count -gt $shown.Count) {
        $lines.Add('')
        $lines.Add("_$($rows.Count - $shown.Count) more detail field(s) in latest.json._")
    }
    return ($lines -join "`n")
}
