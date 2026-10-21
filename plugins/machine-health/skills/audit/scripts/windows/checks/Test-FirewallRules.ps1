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
$baselineHosts = 2

function Get-GroupProgramState {
    <#
    .SYNOPSIS
    One program state for a group of per-version rules; the rule is in
    check-catalog.md section 25, "Items".
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)] [string[]] $States)

    if ('exists' -in $States) { return 'exists' }
    if (@($States | Where-Object { $_ -ne 'not-found' }).Count -eq 0) { return 'not-found' }
    return 'unknown'
}

function Get-RuleField {
    <#
    .SYNOPSIS
    The item fields for one rule, or for a group of per-version rules.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)] [object[]] $Rules,
        [switch] $Grouped
    )

    $first = $Rules[0]
    $fields = [ordered]@{
        rule_name           = if ($Grouped) { $null } else { Format-MachineText $first.Name }
        display_name        = Format-MachineText $first.DisplayName
        program             = Format-MachineText ($Grouped ? $first.ProgramPattern : $first.Program)
        program_state       = $Grouped ? (Get-GroupProgramState -States @($Rules | ForEach-Object { $_.ProgramState })) : $first.ProgramState
        rule_count          = $Rules.Count
        direction           = 'inbound'
        action              = 'allow'
        protocol            = $first.Protocol
        local_port          = Format-MachineText $first.LocalPort
        profile             = $first.Profile
        policy_store_source = $first.Origin
        display_group       = Format-MachineText $first.DisplayGroup
    }
    if ($Grouped) { $fields['rule_names'] = @($Rules | ForEach-Object { Format-MachineText $_.Name } | Sort-Object) }
    return [hashtable]$fields
}

$FailureSummary = 'Firewall rule inventory failed.'
$PassThru = $false
# The envelope turns a throw into a failed UNKNOWN result, which this check
# never reports: any failure becomes the informational result with read_state error.
$CheckBody = {
    try {
        $inventory = Get-FirewallRuleInventory
        $rules = @($inventory.Rules)

        $groups = [ordered]@{}
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($r in $rules) {
            $title = "$($r.DisplayName) ($($r.Program))"
            if (-not $r.ProgramPattern) {
                $items.Add((New-FindingItem -Kind 'firewall' -Identity @($r.Name) -MutedKeys $MutedKeys `
                            -Severity $infoLevel -Title $title -Fields (Get-RuleField -Rules @($r))))
            } elseif (-not $r.PortRead) {
                # A grouped key needs the protocol and port; no key is computed from missing data.
                $items.Add((New-FindingItem -NoKey -NoKeyReason 'protocol and local port unread without elevation' `
                            -Severity $infoLevel -Title $title -Fields (Get-RuleField -Rules @($r))))
            } else {
                $groupKey = "$($r.ProgramPattern.ToLowerInvariant())|$($r.Protocol)|$($r.LocalPort)"
                if (-not $groups.Contains($groupKey)) { $groups[$groupKey] = [System.Collections.Generic.List[object]]::new() }
                $groups[$groupKey].Add($r)
            }
        }
        foreach ($members in $groups.Values) {
            $first = $members[0]
            $items.Add((New-FindingItem -Kind 'firewall' `
                        -Identity @($first.ProgramPattern, 'inbound', $first.Protocol, $first.LocalPort) -MutedKeys $MutedKeys `
                        -Severity $infoLevel -Title "$($first.DisplayName) ($($members.Count) rules, $($first.ProgramPattern))" `
                        -Fields (Get-RuleField -Rules @($members) -Grouped)))
        }
        $items = @($items | Sort-Object { $_.program }, { $_.title })

        $notFound = @($items | Where-Object { $_.program_state -eq 'not-found' }).Count
        $groupedRules = 0
        foreach ($i in $items) { if ($null -eq $i.rule_name) { $groupedRules += $i.rule_count } }
        $summary = if ($inventory.ReadState -eq 'ok') {
            "$($items.Count) foreign inbound allow rule item(s), $notFound for a program that no longer exists."
        } else {
            "Firewall rule inventory could not be read ($($inventory.ReadState)); informational check, nothing judged."
        }

        $detail = @{
            rule_count            = $inventory.RuleCount
            foreign_count         = $inventory.ForeignCount
            candidate_count       = $rules.Count
            not_found_count       = $notFound
            unknown_program_count = @($items | Where-Object { $_.program_state -eq 'unknown' }).Count
            grouped_rule_count    = $groupedRules
            unkeyed_count         = @($items | Where-Object { $null -eq $_.key }).Count
            port_read_state       = $inventory.PortReadState
            port_fallback_reads   = $inventory.PortFallbackReads
            read_state            = $inventory.ReadState
            baseline_hosts        = $baselineHosts
            items_count           = $items.Count
            muted_count           = @($items | Where-Object muted).Count
            items                 = $items
        }
        $result = New-HealthResult -Id $id -Category $category -Os 'windows' -Severity $infoLevel `
            -Summary $summary -Commands $commands -Detail $detail -NeedsAdmin $false
    } catch {
        $result = New-HealthResult -Id $id -Category $category -Os 'windows' -Severity $infoLevel `
            -Summary 'Firewall rule inventory could not be read (error); informational check, nothing judged.' `
            -Commands $commands -NeedsAdmin $false -Notes (Format-MachineText $_.Exception.Message) `
            -Detail @{ read_state = 'error'; baseline_hosts = $baselineHosts; items_count = 0; muted_count = 0; items = @() }
    }
}
. (Join-Path $PSScriptRoot '..\lib\Invoke-HealthCheckEnvelope.ps1')

