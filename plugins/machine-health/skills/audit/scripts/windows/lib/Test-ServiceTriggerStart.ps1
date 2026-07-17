#Requires -Version 7.4

<#
.SYNOPSIS
Returns $true if the named service is configured as trigger-start.

.DESCRIPTION
Windows Service Control Manager (SCM) exposes four start types via the
standard .NET ServiceController (Get-Service) API: Boot, System,
Automatic, Manual, Disabled. It does NOT expose trigger-start as a
separate type -- a trigger-start service reports StartType=Automatic,
but SCM only starts it when a registered trigger fires (device arrival,
domain join, system event, etc.).

The authoritative way to distinguish a pure auto-start service from a
trigger-start service is the presence of the
HKLM:\SYSTEM\CurrentControlSet\Services\<name>\TriggerInfo key. SCM
creates this key when the service has one or more triggers configured
(equivalent to `sc.exe qtriggerinfo <name>` showing one or more
TRIGGERs).

Trigger-start services being Stopped is NORMAL -- they start on demand
and stop themselves when the trigger condition clears. Flagging them as
WARN produces false positives on every modern Windows install.

This wrapper exists as a lib function so Pester tests can mock it
without having to mock Test-Path globally (Test-Path is used in many
other places).
#>

function Test-ServiceTriggerStart {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $Name
    )

    try {
        $path = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name\TriggerInfo"
        return [bool](Test-Path -LiteralPath $path -ErrorAction Stop)
    } catch {
        Write-Verbose "Test-ServiceTriggerStart: registry probe failed for '$Name'. $($_.Exception.Message)"
        return $false
    }
}
