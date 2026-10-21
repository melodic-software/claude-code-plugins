#Requires -Version 7.4

<#
.SYNOPSIS
Reads the Explorer StartupApproved key that governs one startup scope: whether
the owner turned each entry off in Task Manager or Settings.

.DESCRIPTION
Returns { ReadState, Entries }. Entries maps an entry name (a Run value name or
a Startup-folder file name) to { State, RawByte, DisabledAt }:

  State      : enabled | disabled | unknown, decoded from the value's first byte
               through $script:StartupApprovedState
  RawByte    : the first byte, set only when State is unknown
  DisabledAt : the UTC FILETIME stored after the first byte, set only when
               disabled and non-zero

Microsoft does not document this encoding; a byte outside the table stays
unknown with its raw value, so a newly understood byte is one table edit here.
A RunOnce key has no StartupApproved counterpart, so no scope maps to it.
#>

. (Join-Path $PSScriptRoot 'ConvertFrom-FileTimeBytes.ps1')

$script:StartupApprovedRoot = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'

# Startup scope -> the hive and StartupApproved subkey that hold its entries' state.
$script:StartupApprovedKey = @{
    'hkcu'          = 'HKCU:\{0}\Run'
    'hklm'          = 'HKLM:\{0}\Run'
    'hklm-wow64'    = 'HKLM:\{0}\Run32'
    'user-folder'   = 'HKCU:\{0}\StartupFolder'
    'common-folder' = 'HKLM:\{0}\StartupFolder'
}

$script:StartupApprovedState = @{
    2 = 'enabled'
    3 = 'disabled'
}

# The disabled timestamp follows the value's header.
$script:StartupApprovedTimeOffset = 4

$script:StartupApprovedSkippedProperty = @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')

function Read-StartupApproved {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('hkcu', 'hklm', 'hklm-wow64', 'user-folder', 'common-folder')]
        [string] $Scope
    )

    $path = $script:StartupApprovedKey[$Scope] -f $script:StartupApprovedRoot
    $entries = @{}
    try {
        $values = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
    } catch [System.Management.Automation.ItemNotFoundException] {
        return [pscustomobject]@{ ReadState = 'absent'; Entries = $entries }
    } catch [System.UnauthorizedAccessException], [System.Security.SecurityException] {
        return [pscustomobject]@{ ReadState = 'denied'; Entries = $entries }
    } catch {
        Write-Verbose "Read-StartupApproved: $path unreadable. $($_.Exception.Message)"
        return [pscustomobject]@{ ReadState = 'error'; Entries = $entries }
    }

    foreach ($property in @($values | ForEach-Object { $_.PSObject.Properties })) {
        if ($property.Name -in $script:StartupApprovedSkippedProperty) { continue }
        if ($property.Value -isnot [byte[]] -or $property.Value.Length -eq 0) { continue }
        $entries[$property.Name] = ConvertFrom-StartupApprovedValue -Bytes $property.Value
    }
    return [pscustomobject]@{ ReadState = 'ok'; Entries = $entries }
}

function ConvertFrom-StartupApprovedValue {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory = $true)] [byte[]] $Bytes)

    $first = [int]$Bytes[0]
    $state = $script:StartupApprovedState[$first]
    if (-not $state) {
        return [pscustomobject]@{ State = 'unknown'; RawByte = $first; DisabledAt = $null }
    }

    $disabledAt = $null
    if ($state -eq 'disabled') {
        $disabledAt = ConvertFrom-FileTimeBytes -Bytes $Bytes -Offset $script:StartupApprovedTimeOffset
    }
    return [pscustomobject]@{ State = $state; RawByte = $null; DisabledAt = $disabledAt }
}
