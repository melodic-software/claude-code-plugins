#Requires -Version 7.4

<#
.SYNOPSIS
FindingItem helpers for list-style checks: the FindingKey, the item shape, the
ReadState closed set and the unmuted severity fold.

.DESCRIPTION
A FindingKey names one listed item across runs so the owner can mute it:
<kind>:<first 16 hex of SHA-256(lower(kind + "|" + identity fields joined by "|"))>.
The kind list and each kind's identity fields are one-way; changing either
orphans every stored mute in state/mutes.json.

A check receives its muted keys as a -MutedKeys string[] argument; it never
reads mutes.json. A muted item stays in detail.items[] with muted = $true and
no longer counts toward the check's severity.

ReadState records how a source read went: ok | absent | masked | denied |
false-zero | error. A field fed by a state other than ok or absent cannot make
the check OK.
#>

. (Join-Path $PSScriptRoot 'Get-WorstSeverity.ps1')

$script:ReadStates = @('ok', 'absent', 'masked', 'denied', 'false-zero', 'error')

function Get-FindingKey {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('startup', 'task', 'folder', 'app', 'ext', 'listener', 'exclusion', 'detection', 'firewall',
            IgnoreCase = $false)]
        [string] $Kind,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [string[]] $Identity
    )

    $text = ($Kind + '|' + ($Identity -join '|')).ToLowerInvariant()
    $hash = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($text))
    return $Kind + ':' + [System.Convert]::ToHexString($hash, 0, 8).ToLowerInvariant()
}

function New-FindingItem {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure constructor: builds and returns an object, changes no system state.')]
    param(
        [Parameter(Mandatory = $true)] [string] $Kind,
        [Parameter(Mandatory = $true)] [string[]] $Identity,
        [Parameter(Mandatory = $true)] [ValidateSet('OK', 'INFO', 'WARN', 'CRIT', 'UNKNOWN')] [string] $Severity,
        [Parameter(Mandatory = $true)] [string] $Title,
        [AllowNull()] [AllowEmptyCollection()] [string[]] $MutedKeys = @(),
        [hashtable] $Fields = @{}
    )

    $key = Get-FindingKey -Kind $Kind -Identity $Identity
    $item = [ordered]@{
        key      = $key
        severity = $Severity
        muted    = [bool]($key -cin $MutedKeys)
        title    = $Title
    }
    foreach ($name in $Fields.Keys) {
        if ($item.Contains($name)) { throw "New-FindingItem: field '$name' is set by the item itself." }
        $item[$name] = $Fields[$name]
    }
    return [pscustomobject]$item
}

function Assert-ReadState {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0)] [AllowEmptyString()] [string] $State
    )

    if ($State -cnotin $script:ReadStates) {
        throw "ReadState '$State' is not one of $($script:ReadStates -join ', ')."
    }
    return $true
}

function Get-UnmutedSeverity {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyCollection()] [object[]] $Items = @(),
        [AllowEmptyCollection()] [string[]] $ReadState = @()
    )

    $worst = Get-WorstSeverity -Levels @($Items | Where-Object { $_.muted -eq $false } | ForEach-Object { $_.severity })
    foreach ($state in $ReadState) {
        if (-not (Test-ReadStateUsable $state) -and $worst -eq 'OK') { $worst = 'UNKNOWN' }
    }
    return $worst
}

function Test-ReadStateUsable {
    <#
    .SYNOPSIS
    True when a read state lets the fields it feeds count as a clean reading:
    ok or absent. Any other state cannot make a check OK.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0)] [AllowEmptyString()] [string] $ReadState
    )

    [void](Assert-ReadState $ReadState)
    return $ReadState -cin 'ok', 'absent'
}
