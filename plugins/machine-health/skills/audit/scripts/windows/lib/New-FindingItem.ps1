#Requires -Version 7.4

<#
.SYNOPSIS
FindingItem helpers for list-style checks: the FindingKey, the item shape, the
ReadState closed set and the unmuted severity fold.

.DESCRIPTION
A FindingKey names one listed item across runs so the owner can mute it:
<kind>:<first 16 hex of SHA-256(lower(kind + "|" + identity fields joined by "|"))>.
The kind list and each kind's identity fields are one-way; changing either
orphans every stored mute in state/mutes.json. A process key's identity is
the lowercased image file name (msedge.exe), never the process id.

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
            'process', IgnoreCase = $false)]
        [string] $Kind,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [string[]] $Identity
    )

    $text = ($Kind + '|' + ($Identity -join '|')).ToLowerInvariant()
    $hash = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($text))
    return $Kind + ':' + [System.Convert]::ToHexString($hash, 0, 8).ToLowerInvariant()
}

# Machine-derived text (names, paths, event text) is untrusted display data:
# capped at this length, with control, escape and bidi-override characters
# replaced so it cannot add lines or reorder what a reader sees.
$script:MachineTextMaxLength = 300
$script:MachineTextUnsafe = '[\x00-\x1F\x7F-\x9F\u061C\u200E\u200F\u2028\u2029\u202A-\u202E\u2066-\u2069]'

function Format-MachineText {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Position = 0)] [AllowNull()] [object] $Text)

    if ($null -eq $Text) { return $null }
    $clean = [regex]::Replace([string]$Text, $script:MachineTextUnsafe, ' ')
    if ($clean.Length -gt $script:MachineTextMaxLength) {
        $clean = $clean.Substring(0, $script:MachineTextMaxLength - 3) + '...'
    }
    return $clean
}

function New-FindingItem {
    <#
    .SYNOPSIS
    Builds one FindingItem. The title passes through Format-MachineText.

    .DESCRIPTION
    -NoKey builds an item with no stable identity: key is $null, the item can
    never be muted, and -NoKeyReason is recorded as unkeyed_reason. A check
    uses it when the identity fields could not be read, so no key is ever
    computed from missing data.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Keyed')]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure constructor: builds and returns an object, changes no system state.')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Keyed')] [string] $Kind,
        [Parameter(Mandatory = $true, ParameterSetName = 'Keyed')] [string[]] $Identity,
        [Parameter(Mandatory = $true, ParameterSetName = 'Unkeyed')] [switch] $NoKey,
        [Parameter(Mandatory = $true, ParameterSetName = 'Unkeyed')] [ValidateNotNullOrEmpty()] [string] $NoKeyReason,
        [Parameter(Mandatory = $true)] [ValidateSet('OK', 'INFO', 'WARN', 'CRIT', 'UNKNOWN')] [string] $Severity,
        [Parameter(Mandatory = $true)] [string] $Title,
        [Parameter(ParameterSetName = 'Keyed')] [AllowNull()] [AllowEmptyCollection()] [string[]] $MutedKeys = @(),
        [hashtable] $Fields = @{}
    )

    $key = if ($NoKey) { $null } else { Get-FindingKey -Kind $Kind -Identity $Identity }
    $item = [ordered]@{
        key      = $key
        severity = $Severity
        muted    = $null -ne $key -and [bool]($key -cin $MutedKeys)
        title    = Format-MachineText $Title
    }
    if ($NoKey) { $item['unkeyed_reason'] = $NoKeyReason }
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
