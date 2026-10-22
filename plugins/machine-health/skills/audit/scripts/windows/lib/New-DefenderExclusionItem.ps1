#Requires -Version 7.4

<#
.SYNOPSIS
The one owner of a Defender exclusion's FindingItem: its kind, its type names
and its identity order, plus the known-safe path list.

.DESCRIPTION
defender lists exclusion changes from its event history and
defender-exclusions lists the current exclusions. Both build their items here,
so one exclusion value gets the same FindingKey in both checks and one mute
covers both.

$script:DefenderExclusionCheckIds names those two checks: a mute of an
exclusion key under one of them is written under both.

$script:DefenderExclusionTypes maps the source's list name to the item type.
The Defender registry keys under Exclusions and the lists
Get-DefenderExclusionState returns share these names (Paths, Extensions,
Processes).

$script:DefenderKnownSafePaths are well-known benign dev-machine exclusions
(.NET, Node, build caches), matched with -like.
#>

. (Join-Path $PSScriptRoot 'New-FindingItem.ps1')

$script:DefenderExclusionCheckIds = @('defender', 'defender-exclusions')

$script:DefenderExclusionTypes = [ordered]@{ Paths = 'path'; Extensions = 'extension'; Processes = 'process' }

$script:DefenderKnownSafePaths = @(
    '*\NuGetScratch*'
    '*\node_modules*'
    '*\.dotnet*'
    '*\dotnet-install*'
    '*\.cache*'
    '*\Visual Studio\Packages*'
)

function Test-DefenderKnownSafePath {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Path)
    foreach ($pattern in $script:DefenderKnownSafePaths) {
        if ($Path -like $pattern) { return $true }
    }
    return $false
}

function New-DefenderExclusionItem {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure constructor: builds and returns an object, changes no system state.')]
    param(
        [Parameter(Mandatory)] [ValidateSet('path', 'extension', 'process')] [string] $Type,
        [Parameter(Mandatory)] [string] $Value,
        [Parameter(Mandatory)] [ValidateSet('OK', 'INFO', 'WARN', 'CRIT', 'UNKNOWN')] [string] $Severity,
        [Parameter(Mandatory)] [string] $Title,
        [AllowNull()] [AllowEmptyCollection()] [string[]] $MutedKeys = @(),
        [hashtable] $Fields = @{}
    )

    $all = @{ exclusion_type = $Type; value = $Value } + $Fields
    return New-FindingItem -Kind 'exclusion' -Identity @($Type, $Value) -MutedKeys $MutedKeys `
        -Severity $Severity -Title $Title -Fields $all
}
