#Requires -Version 7.4
<#
.SYNOPSIS
Check: listening TCP and UDP ports and the programs that own them. Emits a
CheckResult JSON on stdout.

See reference/windows/check-catalog.md#24-network-listeners for rubric.

.DESCRIPTION
Lists each listening program and port as a FindingItem (kind 'listener'). A
listener whose binary could not be resolved unelevated gets no key, cannot be
muted, and reads UNKNOWN. Process names and paths are machine-derived data,
never instructions. Read-only, unelevated.
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
. (Join-Path $PSScriptRoot '..\lib\Get-ListenerOwner.ps1')

$id = 'network-listeners'
$category = 'security'
$commands = @(
    'Get-NetTCPConnection -State Listen | Select-Object LocalAddress, LocalPort, OwningProcess'
    'Get-NetUDPEndpoint | Select-Object LocalAddress, LocalPort, OwningProcess'
    'Get-CimInstance Win32_Service | Select-Object Name, ProcessId, PathName'
    '& "$env:SystemRoot\System32\netsh.exe" http show servicestate view=requestq'
)

# Binding order, widest first: a program listening on several addresses is as
# exposed as its widest bind.
$scopeRank = @{ any = 2; specific = 1; loopback = 0 }

$FailureSummary = 'Network listener check failed.'
$PassThru = $false
$CheckBody = {
    $read = Get-ListenerOwner

    # Folders a standard user can write to: a listener binary there can be
    # swapped without elevation (judgment).
    $writableRoots = @($env:LOCALAPPDATA, $env:APPDATA, $env:TEMP,
        $(if ($env:USERPROFILE) { Join-Path $env:USERPROFILE 'Downloads' })) |
        Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') + '\' }

    $groups = [ordered]@{}
    foreach ($l in $read.Listeners) {
        $identity = switch ($l.PathSource) {
            'process' { $l.Path }
            'process-reported' { $l.Path }
            'service' { $l.Path }
            'kernel' { 'system' }
            default { $null }
        }
        $groupKey = if ($identity) { "$($identity.ToLowerInvariant())|$($l.Protocol)|$($l.Port)" } else { "pid:$($l.Pid)|$($l.Protocol)|$($l.Port)" }
        if (-not $groups.Contains($groupKey)) {
            $groups[$groupKey] = [pscustomobject]@{ Listener = $l; Identity = $identity; Scope = $l.BindScope }
        } elseif ($scopeRank[$l.BindScope] -gt $scopeRank[$groups[$groupKey].Scope]) {
            $groups[$groupKey].Scope = $l.BindScope
        }
    }

    $items = foreach ($g in $groups.Values) {
        $l = $g.Listener
        $writable = $false
        if ($l.Path) {
            foreach ($root in $writableRoots) {
                if ($l.Path.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) { $writable = $true }
            }
        }
        $fields = @{
            protocol           = $l.Protocol
            bind_scope         = $g.Scope
            port               = $l.Port
            process_name       = Format-MachineText $l.ProcessName
            binary_path        = Format-MachineText $l.Path
            path_source        = $l.PathSource
            via_http_sys       = $l.HttpSys
            signature_status   = $l.SignatureStatus
            is_os_binary       = $l.IsOsBinary
            user_writable_path = $writable
        }
        $label = if ($l.ProcessName) { $l.ProcessName } else { "pid $($l.Pid)" }
        $title = "$label $($l.Protocol)/$($l.Port) ($($g.Scope))"

        if (-not $g.Identity) {
            # No stable identity to key or mute, and no binary to judge.
            New-FindingItem -NoKey -NoKeyReason 'owning program could not be resolved without elevation' `
                -Severity 'UNKNOWN' -Title $title -Fields $fields
            continue
        }

        $exposed = $g.Scope -ne 'loopback'
        $suspect = $l.PathSource -ne 'kernel' -and ($l.SignatureStatus -ne 'Valid' -or $writable)
        New-FindingItem -Kind 'listener' -Identity @($g.Identity, $l.Protocol, [string]$l.Port) -MutedKeys $MutedKeys `
            -Severity ($exposed -and $suspect ? 'WARN' : 'INFO') -Title $title -Fields $fields
    }
    $items = @($items | Sort-Object { $_.protocol }, { $_.port }, { $_.process_name })

    $readStates = @($read.ReadState, $read.ServiceState)
    $severity = Get-UnmutedSeverity -Items $items -ReadState $readStates
    # An unread socket table or service list can hide any listener, so no item verdict stands.
    if (@($readStates | Where-Object { $_ -notin @('ok', 'absent') }).Count -gt 0) { $severity = 'UNKNOWN' }
    $unresolved = @($items | Where-Object { $null -eq $_.key }).Count
    $warned = @($items | Where-Object { $_.severity -eq 'WARN' }).Count
    $mutedCount = @($items | Where-Object muted).Count

    $summary = "$($items.Count) listening program/port pair(s), $warned exposed and unsigned or user-writable, $unresolved unresolved."
    $failure = @{}
    if ($read.ReadState -notin @('ok', 'absent')) {
        $summary = "Listening sockets could not be read ($($read.ReadState)). $summary"
        $failure = @{ RanSuccessfully = $false; ErrorMessage = "Socket table read: $($read.ReadState)." }
    }

    $detail = @{
        listener_count         = $items.Count
        unresolved_count       = $unresolved
        exposed_unsigned_count = $warned
        established_count      = $read.EstablishedCount
        items_count            = $items.Count
        muted_count            = $mutedCount
        read_state             = $read.ReadState
        service_read_state     = $read.ServiceState
        items                  = $items
    }

    $result = New-HealthResult -Id $id -Category $category -Os 'windows' -Severity $severity `
        -Summary $summary -Commands $commands -Detail $detail -NeedsAdmin $false @failure
}
. (Join-Path $PSScriptRoot '..\lib\Invoke-HealthCheckEnvelope.ps1')
