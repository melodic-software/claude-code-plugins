#Requires -Version 7.4

<#
.SYNOPSIS
Return the HResult of the exception behind an error record, unwrapping the
MethodInvocationException PowerShell adds around a failed .NET call.

.DESCRIPTION
$SharingViolationHResult is ERROR_SHARING_VIOLATION as an HRESULT: another
handle's share mode forbids the open or the replace. Enter-RunLock reads it as
"the lock is held"; Write-StateFile retries on it.
#>

$script:SharingViolationHResult = 0x80070020

function Get-InnerHResult {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)] [System.Management.Automation.ErrorRecord] $ErrorRecord
    )

    $ex = $ErrorRecord.Exception
    if ($ex -is [System.Management.Automation.MethodInvocationException] -and $ex.InnerException) {
        $ex = $ex.InnerException
    }
    return $ex.HResult
}
