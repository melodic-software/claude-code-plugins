#Requires -Version 7.4

<#
.SYNOPSIS
Inventories the inbound allow firewall rules that did not ship with Windows
and returns plain FirewallRuleRecords plus a ReadState.

.DESCRIPTION
Bulk reads only, joined on the filter's InstanceID = the rule's Name (one call
per rule costs about a second each):
  - every rule in the ActiveStore with -TracePolicyStore (origin fields);
  - the names in the read-only SystemDefaults store: a rule whose Name is
    there shipped with Windows;
  - every application filter (the rule's program);
  - every port filter (protocol and local port).

A candidate is a foreign rule (locally stored, Name not in SystemDefaults;
Group Policy, MDM and dynamic rules are dropped) that is enabled, inbound,
allow, and bound to a program other than Any or System.

Unelevated, the bulk port-filter read stops at the first filter it may not
open and returns the rest. A versioned candidate (its program path has a
dotted-version folder, so the check groups it and keys it by protocol and
port) that the bulk read missed gets its own port-filter read, within a call
cap and a time budget; whatever stays unread keeps Protocol and LocalPort
$null and PortRead $false.

ProgramState is three-valued: Test-Path returns False for an existing file
under a folder the caller cannot traverse, but then also writes an
access-denied error record. False with an error record is 'unknown'; False
with none is 'not-found'.

Read-only, unelevated.
#>

$script:PortFallbackMaxCalls = 20
$script:PortFallbackBudgetMs = 15000
$script:VersionSegment = '^\d+(\.\d+)+$'

function Get-FirewallReadState {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)] [System.Management.Automation.ErrorRecord] $ErrorRecord)

    if ($ErrorRecord.CategoryInfo.Category -eq 'PermissionDenied' -or
        $ErrorRecord.Exception -is [System.UnauthorizedAccessException]) { return 'denied' }
    return 'error'
}

function Get-VersionedProgramPattern {
    <#
    .SYNOPSIS
    Returns the program path with each dotted-version folder replaced by '*',
    or $null when the path has none.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)] [string] $Path)

    $segments = $Path -split '\\'
    $versioned = $false
    $pattern = foreach ($s in $segments) {
        if ($s -match $script:VersionSegment) { $versioned = $true; '*' } else { $s }
    }
    return $versioned ? ($pattern -join '\') : $null
}

function Get-ProgramState {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)] [string] $Path)

    $probeErrors = $null
    $exists = Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue -ErrorVariable probeErrors
    if ($exists) { return 'exists' }
    if (@($probeErrors).Count -gt 0) { return 'unknown' }
    return 'not-found'
}

function ConvertTo-PortField {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory = $true)] $Filter)

    [pscustomobject]@{
        Protocol  = [string]$Filter.Protocol
        LocalPort = (@($Filter.LocalPort) | ForEach-Object { [string]$_ }) -join ','
    }
}

function Get-FirewallRuleInventory {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $result = [pscustomobject]@{
        ReadState         = 'ok'
        PortReadState     = 'ok'
        PortFallbackReads = 0
        RuleCount         = 0
        ForeignCount      = 0
        Rules             = @()
    }

    try {
        $active = @(Get-NetFirewallRule -PolicyStore ActiveStore -TracePolicyStore -ErrorAction Stop)
        $defaultNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($d in @(Get-NetFirewallRule -PolicyStore SystemDefaults -ErrorAction Stop)) { [void]$defaultNames.Add([string]$d.Name) }
        $programs = @{}
        foreach ($f in @(Get-NetFirewallApplicationFilter -PolicyStore ActiveStore -All -ErrorAction Stop)) {
            $programs[[string]$f.InstanceID] = [string]$f.Program
        }
    } catch {
        $result.ReadState = Get-FirewallReadState -ErrorRecord $_
        return $result
    }

    $portErrors = $null
    $ports = @{}
    foreach ($p in @(Get-NetFirewallPortFilter -PolicyStore ActiveStore -All -ErrorAction SilentlyContinue -ErrorVariable portErrors)) {
        $ports[[string]$p.InstanceID] = ConvertTo-PortField -Filter $p
    }
    if (@($portErrors).Count -gt 0) { $result.PortReadState = Get-FirewallReadState -ErrorRecord @($portErrors)[0] }

    $result.RuleCount = $active.Count
    $foreign = @($active | Where-Object {
            [string]$_.PolicyStoreSourceType -eq 'Local' -and -not $defaultNames.Contains([string]$_.Name)
        })
    $result.ForeignCount = $foreign.Count

    $budget = [System.Diagnostics.Stopwatch]::StartNew()
    $states = @{}
    $rules = foreach ($r in $foreign) {
        if ([string]$r.Enabled -ne 'True' -or [string]$r.Direction -ne 'Inbound' -or [string]$r.Action -ne 'Allow') { continue }
        $program = $programs[[string]$r.Name]
        if ([string]::IsNullOrWhiteSpace($program) -or $program -in @('Any', 'System')) { continue }

        $expanded = [System.Environment]::ExpandEnvironmentVariables($program)
        $pattern = Get-VersionedProgramPattern -Path $expanded
        $port = $ports[[string]$r.Name]
        if ($null -eq $port -and $pattern -and
            $result.PortFallbackReads -lt $script:PortFallbackMaxCalls -and
            $budget.ElapsedMilliseconds -lt $script:PortFallbackBudgetMs) {
            $result.PortFallbackReads++
            try {
                $one = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $r -ErrorAction Stop | Select-Object -First 1
                if ($one) { $port = ConvertTo-PortField -Filter $one }
            } catch {
                Write-Verbose "Get-FirewallRuleInventory: port filter for one rule unreadable ($($_.Exception.Message))."
            }
        }

        $stateKey = $expanded.ToLowerInvariant()
        if (-not $states.ContainsKey($stateKey)) { $states[$stateKey] = Get-ProgramState -Path $expanded }

        [pscustomobject]@{
            Name           = [string]$r.Name
            DisplayName    = [string]$r.DisplayName
            Program        = $expanded
            ProgramPattern = $pattern
            ProgramState   = $states[$stateKey]
            Origin         = [string]$r.PolicyStoreSource
            Protocol       = if ($port) { $port.Protocol } else { $null }
            LocalPort      = if ($port) { $port.LocalPort } else { $null }
            PortRead       = $null -ne $port
            Profile        = [string]$r.Profile
            DisplayGroup   = [string]$r.DisplayGroup
        }
    }

    $result.Rules = @($rules)
    return $result
}
