#Requires -Version 7.4

<#
.SYNOPSIS
Read the current Defender exclusion lists (path, extension, process) through
the native MSFT_MpPreference CIM class.

.DESCRIPTION
Returns { ReadState, Paths, Extensions, Processes }. ReadState is ok, masked,
denied or error; every list is empty unless ReadState is ok.

Defender hides the lists from a standard user by answering with a placeholder
string, so an unelevated process is masked without reading anything. An
elevated read that still returns the placeholder (exclusions hidden from local
admins too) is masked as well. The placeholder never leaves this file.

The class is read from its own CIM namespace rather than through the Defender
module, which PowerShell 7 loads through Windows PowerShell compatibility.
#>

. (Join-Path $PSScriptRoot 'Test-IsElevated.ps1')

$script:DefenderPreferenceNamespace = 'root/Microsoft/Windows/Defender'
$script:DefenderPreferenceClass = 'MSFT_MpPreference'

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

    $lists = foreach ($name in 'ExclusionPath', 'ExclusionExtension', 'ExclusionProcess') {
        , @($pref.$name | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    if (@($lists | ForEach-Object { $_ } | Where-Object { $_ -like 'N/A*' }).Count -gt 0) { return $state }

    $state.ReadState = 'ok'
    $state.Paths = [string[]]$lists[0]
    $state.Extensions = [string[]]$lists[1]
    $state.Processes = [string[]]$lists[2]
    return $state
}
