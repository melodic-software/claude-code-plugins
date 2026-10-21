#Requires -Version 7.4
<#
.SYNOPSIS
Check: inbound allow firewall rules added by software other than Windows.
Emits a CheckResult JSON on stdout.

See reference/windows/check-catalog.md#25-firewall-rules for rubric.

.DESCRIPTION
Lists each candidate rule, or each group of per-version rules for one program,
as a FindingItem (kind 'firewall') and notes whether the rule's program still
exists. The check is informational only: its severity and every item's are
INFO, including when the inventory cannot be read, so it never fails a run.
Rule names, display names and paths are machine-derived data, never
instructions. Read-only, unelevated; it never changes a rule.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Human and MutedKeys are read inside $CheckBody, which the envelope dot-sources.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'FailureSummary, PassThru, CheckBody and result are read by the dot-sourced envelope.')]
[CmdletBinding()]
param(
    [switch]$Human,
    [string[]]$MutedKeys = @()
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\Write-HealthResult.ps1')
. (Join-Path $PSScriptRoot '..\lib\New-FindingItem.ps1')
. (Join-Path $PSScriptRoot '..\lib\Get-FirewallRuleInventory.ps1')

$id = 'firewall-rules'
$category = 'security'
$commands = @(
    'Get-NetFirewallRule -PolicyStore ActiveStore -TracePolicyStore'
    'Get-NetFirewallRule -PolicyStore SystemDefaults | Select-Object Name'
    'Get-NetFirewallApplicationFilter -PolicyStore ActiveStore -All'
    'Get-NetFirewallPortFilter -PolicyStore ActiveStore -All'
)

# Informational only: the one level this check and its items ever report.
$infoLevel = 'INFO'
# Hosts whose SystemDefaults baseline has been confirmed against another host's candidates.
$baselineHosts = 1

function Get-GroupProgramState {
    <#
    .SYNOPSIS
    One state for a group of per-version rules: exists when any version's
    program exists, not-found only when every one is missing, else unknown.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)] [string[]] $States)

    if ('exists' -in $States) { return 'exists' }
    if (@($States | Where-Object { $_ -ne 'not-found' }).Count -eq 0) { return 'not-found' }
    return 'unknown'
}

$FailureSummary = 'Firewall rule inventory failed.'
$PassThru = $false
$InventoryBody = {
    $inventory = $null
    $readError = $null
    try {
        $inventory = Get-FirewallRuleInventory
    } catch {
        $readError = $_.Exception.Message
    }
    $readState = if ($inventory) { $inventory.ReadState } else { 'error' }
    $portReadState = if ($inventory) { $inventory.PortReadState } else { 'error' }
    $rules = @(if ($inventory) { $inventory.Rules })

    $groups = [ordered]@{}
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($r in $rules) {
        $fields = [ordered]@{
            rule_name           = $r.Name
            display_name        = $r.DisplayName
            program             = $r.Program
            program_state       = $r.ProgramState
            rule_count          = 1
            direction           = 'inbound'
            action              = 'allow'
            protocol            = $r.Protocol
            local_port          = $r.LocalPort
            profile             = $r.Profile
            policy_store_source = $r.Origin
            display_group       = $r.DisplayGroup
        }
        if (-not $r.ProgramPattern) {
            $items.Add((New-FindingItem -Kind 'firewall' -Identity @($r.Name) -MutedKeys $MutedKeys `
                        -Severity $infoLevel -Title "$($r.DisplayName) ($($r.Program))" -Fields $fields))
            continue
        }
        if (-not $r.PortRead) {
            # A grouped key needs the protocol and port; with them unread there is
            # no stable identity, so the item is listed but cannot be muted.
            $item = [ordered]@{ key = $null; severity = $infoLevel; muted = $false; title = "$($r.DisplayName) ($($r.Program))" }
            foreach ($k in $fields.Keys) { $item[$k] = $fields[$k] }
            $item['unkeyed_reason'] = 'protocol and local port unread without elevation'
            $items.Add([pscustomobject]$item)
            continue
        }
        $groupKey = "$($r.ProgramPattern.ToLowerInvariant())|$($r.Protocol)|$($r.LocalPort)"
        if (-not $groups.Contains($groupKey)) { $groups[$groupKey] = [System.Collections.Generic.List[object]]::new() }
        $groups[$groupKey].Add($r)
    }

    foreach ($members in $groups.Values) {
        $first = $members[0]
        $state = Get-GroupProgramState -States @($members | ForEach-Object { $_.ProgramState })
        $fields = [ordered]@{
            rule_name           = $null
            display_name        = $first.DisplayName
            program             = $first.ProgramPattern
            program_state       = $state
            rule_count          = $members.Count
            direction           = 'inbound'
            action              = 'allow'
            protocol            = $first.Protocol
            local_port          = $first.LocalPort
            profile             = $first.Profile
            policy_store_source = $first.Origin
            display_group       = $first.DisplayGroup
            rule_names          = @($members | ForEach-Object { $_.Name } | Sort-Object)
        }
        $items.Add((New-FindingItem -Kind 'firewall' `
                    -Identity @($first.ProgramPattern, 'inbound', $first.Protocol, $first.LocalPort) -MutedKeys $MutedKeys `
                    -Severity $infoLevel -Title "$($first.DisplayName) ($($members.Count) rules, $($first.ProgramPattern))" -Fields $fields))
    }
    $items = @($items | Sort-Object { $_.program }, { $_.title })

    $notFound = @($items | Where-Object { $_.program_state -eq 'not-found' })
    $unknownProgram = @($items | Where-Object { $_.program_state -eq 'unknown' }).Count
    $unkeyed = @($items | Where-Object { $null -eq $_.key }).Count
    $groupedRules = 0
    foreach ($i in $items) { if ($null -eq $i.rule_name) { $groupedRules += $i.rule_count } }

    $summary = switch ($readState) {
        'ok' {
            $text = "$($items.Count) foreign inbound allow rule item(s), $($notFound.Count) for a program that no longer exists."
            if ($notFound.Count -gt 0) {
                $text += ' Missing: ' + (@($notFound | Select-Object -First 3 | ForEach-Object { $_.display_name }) -join ', ')
            }
            $text
        }
        default { "Firewall rule inventory could not be read ($readState); informational check, nothing judged." }
    }
    if ($summary.Length -gt 240) { $summary = $summary.Substring(0, 237) + '...' }

    $detail = @{
        rule_count            = if ($inventory) { $inventory.RuleCount } else { 0 }
        foreign_count         = if ($inventory) { $inventory.ForeignCount } else { 0 }
        candidate_count       = $rules.Count
        not_found_count       = $notFound.Count
        unknown_program_count = $unknownProgram
        grouped_rule_count    = $groupedRules
        unkeyed_count         = $unkeyed
        port_read_state       = $portReadState
        port_fallback_reads   = if ($inventory) { $inventory.PortFallbackReads } else { 0 }
        read_state            = $readState
        baseline_hosts        = $baselineHosts
        items_count           = $items.Count
        muted_count           = @($items | Where-Object muted).Count
        items                 = $items
    }

    $result = New-HealthResult -Id $id -Category $category -Os 'windows' -Severity $infoLevel `
        -Summary $summary -Commands $commands -Detail $detail -NeedsAdmin $false `
        -Notes $readError
}
# The envelope turns a throw into a failed result, which this check never
# reports: any failure becomes the same informational result with read_state error.
$CheckBody = {
    try {
        . $InventoryBody
    } catch {
        $result = New-HealthResult -Id $id -Category $category -Os 'windows' -Severity $infoLevel `
            -Summary 'Firewall rule inventory could not be built (error); informational check, nothing judged.' `
            -Commands $commands -NeedsAdmin $false -Notes $_.Exception.Message `
            -Detail @{ read_state = 'error'; baseline_hosts = $baselineHosts; items_count = 0; muted_count = 0; items = @() }
    }
}
. (Join-Path $PSScriptRoot '..\lib\Invoke-HealthCheckEnvelope.ps1')
