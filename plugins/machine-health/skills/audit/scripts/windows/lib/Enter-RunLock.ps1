#Requires -Version 7.4

<#
.SYNOPSIS
Take an exclusive lock on <StateDir>/<Name>.lock and return its open handle.

.DESCRIPTION
The lock is the open FileStream itself (FileShare.None): dispose it to release
the lock; a process that exits releases it too. The file stays on disk.

The orchestrator takes run.lock for a whole audit; Set-ApprovalState takes
approvals.lock across its read, modify and replace, so setup is not blocked for
the length of an audit.

Returns $null when another handle still holds the lock after -TimeoutSeconds
(default 0: no wait). Any other failure throws.
#>

. (Join-Path $PSScriptRoot 'Get-InnerHResult.ps1')

function Enter-RunLock {
    [CmdletBinding()]
    [OutputType([System.IO.FileStream])]
    param(
        [Parameter(Mandatory = $true)] [string] $StateDir,
        [Parameter(Mandatory = $true)] [ValidatePattern('^[a-z][a-z0-9-]*$')] [string] $Name,
        [ValidateRange(0, 600)] [int] $TimeoutSeconds = 0
    )

    $lockPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
        (Join-Path $StateDir "$Name.lock"))
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        try {
            return [System.IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
        } catch {
            if ((Get-InnerHResult $_) -ne $script:SharingViolationHResult) { throw }
        }
        if ($watch.Elapsed.TotalSeconds -ge $TimeoutSeconds) { return $null }
        Start-Sleep -Milliseconds 100
    }
}
