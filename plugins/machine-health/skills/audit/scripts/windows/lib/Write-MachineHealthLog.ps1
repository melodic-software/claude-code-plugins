#Requires -Version 7.4

<#
.SYNOPSIS
Append a timestamped line to a machine-health log file.

.DESCRIPTION
Canonical log-line writer for machine-health. Dot-sourced by both the
orchestrator (run.log) and library helpers (egress, approval migration).

Fail-safe: an empty or missing $LogPath silently returns; an Add-Content
failure logs to Write-Verbose rather than throwing. Callers that need
hard error semantics should append directly with -ErrorAction Stop.
#>

function Write-MachineHealthLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string] $Message,
        [string] $LogPath
    )
    if (-not $LogPath) { return }
    $line = "$((Get-Date).ToString('o')) $Message"
    try {
        Add-Content -LiteralPath $LogPath -Value $line -Encoding utf8 -ErrorAction Stop
    } catch {
        Write-Verbose "Write-MachineHealthLog: append failed. $($_.Exception.Message)"
    }
}
