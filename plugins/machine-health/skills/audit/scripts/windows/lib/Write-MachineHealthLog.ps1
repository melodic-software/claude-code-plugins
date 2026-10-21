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

-ToStderr writes the line to stderr instead of any file: the orchestrator
binds it when the state folder may not be written, so stdout stays clean for
the run snapshot.
#>

function Write-MachineHealthLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string] $Message,
        [string] $LogPath,
        [switch] $ToStderr
    )
    $line = "$((Get-Date).ToString('o')) $Message"
    if ($ToStderr) {
        [Console]::Error.WriteLine($line)
        return
    }
    if (-not $LogPath) { return }
    try {
        Add-Content -LiteralPath $LogPath -Value $line -Encoding utf8 -ErrorAction Stop
    } catch {
        Write-Verbose "Write-MachineHealthLog: append failed. $($_.Exception.Message)"
    }
}
