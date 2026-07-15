#Requires -Version 7.4

<#
.SYNOPSIS
Returns [bool] indicating whether the current process has Administrator privileges.

.DESCRIPTION
No side effects. Does not prompt. Safe to call unconditionally.
Returns $false on non-Windows hosts.
#>

function Test-IsElevated {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if (-not $IsWindows) {
        return $false
    }

    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Test-IsElevated
}
