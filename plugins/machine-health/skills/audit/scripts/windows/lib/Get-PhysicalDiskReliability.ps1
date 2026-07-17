#Requires -Version 7.4

<#
.SYNOPSIS
Thin wrapper around Get-StorageReliabilityCounter for testability.

.DESCRIPTION
The storage cmdlets require Microsoft.Management.Infrastructure.CimInstance
typed inputs, which PowerShell's parameter-binding transformation enforces
before Pester mocks can intercept. That makes the real cmdlet impossible to
swap for a pscustomobject fixture in tests.

This wrapper takes an untyped Disk input, delegates to the real cmdlet, and
returns the counter payload -- or $null when the counter is unavailable
(common on USB drives, some legacy SATA, and WSL passthrough). Callers
consume it exactly like the raw cmdlet output.

Tests mock Get-PhysicalDiskReliability directly and side-step the CIM type
constraint entirely.
#>

function Get-PhysicalDiskReliability {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true, Position = 0)] $Disk
    )

    try {
        return $Disk | Get-StorageReliabilityCounter -ErrorAction Stop
    } catch {
        $name = $Disk.FriendlyName
        Write-Verbose "Get-PhysicalDiskReliability: no counter for '$name'. $($_.Exception.Message)"
        return $null
    }
}
