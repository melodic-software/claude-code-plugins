#Requires -Version 7.4

<#
.SYNOPSIS
Read the current Defender exclusion lists (path, extension, process) through
the native MSFT_MpPreference CIM class.

.DESCRIPTION
Returns { ReadState, Paths, Extensions, Processes }. ReadState is ok, masked,
denied or error; every list is empty unless ReadState is ok. The list names
match the keys of the shared exclusion type map (New-DefenderExclusionItem.ps1).

Defender hides the exclusion lists from accounts the HideExclusionsFromLocalUsers
and HideExclusionsFromLocalAdmins settings cover, answering each list with a
single placeholder sentence instead of the entries:
https://learn.microsoft.com/en-us/windows/client-management/mdm/defender-csp#configurationhideexclusionsfromlocalusers
(as of 2026-10-21; recheck when a Defender release changes who may read
exclusions or how a hidden list answers). An unelevated process is masked
without reading anything. An elevated read is masked when a list holds exactly
one entry that is not a rooted or environment-variable path, an extension or a
file name, which is the placeholder's shape in any language. The placeholder
never leaves this file.

The class is read from its own CIM namespace rather than through the Defender
module, which PowerShell 7 loads through Windows PowerShell compatibility.
#>

. (Join-Path $PSScriptRoot 'Test-IsElevated.ps1')

$script:DefenderPreferenceNamespace = 'root/Microsoft/Windows/Defender'
$script:DefenderPreferenceClass = 'MSFT_MpPreference'

function Test-DefenderExclusionEntryShape {
    param([AllowEmptyString()] [string] $Entry)
    if ([System.IO.Path]::IsPathRooted($Entry) -or $Entry.StartsWith('%')) { return $true }
    return $Entry.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -lt 0
}

function Get-DefenderExclusionState {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $state = [pscustomobject]@{ ReadState = 'masked'; Paths = @(); Extensions = @(); Processes = @() }
    if (-not (Test-IsElevated)) { return $state }

    try {
        $pref = Get-CimInstance -Namespace $script:DefenderPreferenceNamespace -ClassName $script:DefenderPreferenceClass -ErrorAction Stop
    } catch {
        $denied = $_.Exception -is [System.UnauthorizedAccessException] -or
            "$($_.Exception.PSObject.Properties['NativeErrorCode']?.Value)" -eq 'AccessDenied'
        $state.ReadState = $denied ? 'denied' : 'error'
        Write-Verbose "Get-DefenderExclusionState: $($_.Exception.Message)"
        return $state
    }
    if ($null -eq $pref) {
        $state.ReadState = 'error'
        return $state
    }

    $lists = foreach ($name in 'ExclusionPath', 'ExclusionExtension', 'ExclusionProcess') {
        , [string[]]@($pref.$name | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    foreach ($list in $lists) {
        if ($list.Count -eq 1 -and -not (Test-DefenderExclusionEntryShape $list[0])) { return $state }
    }

    $state.ReadState = 'ok'
    $state.Paths = $lists[0]
    $state.Extensions = $lists[1]
    $state.Processes = $lists[2]
    return $state
}
