#Requires -Version 7.4

<#
.SYNOPSIS
Returns the display label for a check id: the bare id for a shipped check, the
id suffixed with ' [custom]' for one registered by the machine-local overlay.

.DESCRIPTION
One label format for every surface that names a check (report findings, the
summary table, the pre-run banner's coverage list), so a custom check reads the
same everywhere.

Neutrally named: cross-OS formatting, no Windows-specific logic.
#>

function Format-CheckLabel {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)] [string] $Id,
        [AllowEmptyCollection()]
        [string[]] $CustomIds = @()
    )
    return ($CustomIds -contains $Id) ? "$Id [custom]" : $Id
}
