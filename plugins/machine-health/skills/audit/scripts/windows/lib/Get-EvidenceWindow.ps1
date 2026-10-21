#Requires -Version 7.4

<#
.SYNOPSIS
Finds the earliest moment from which this user's launch records can be trusted
to be complete.

.DESCRIPTION
Returns { ReadState, Start, Days, Sources }:

  Start   : UTC, the later of the OS install date and the user profile's
            creation time; launch records cannot predate either
  Days    : whole days from Start to now
  Sources : one { Name, Start } per input (os-install, profile-created)

A source that cannot be read is left out of Sources and turns ReadState to
error, since Start may then be earlier than the records reach. Both missing
leaves Start and Days $null.
#>

$script:OsVersionKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'

function Get-EvidenceWindow {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $sources = [System.Collections.Generic.List[pscustomobject]]::new()
    $state = 'ok'

    try {
        $seconds = (Get-ItemProperty -LiteralPath $script:OsVersionKey -Name 'InstallDate' -ErrorAction Stop).InstallDate
        $sources.Add([pscustomobject]@{
                Name  = 'os-install'
                Start = [DateTimeOffset]::FromUnixTimeSeconds([long]$seconds).UtcDateTime
            })
    } catch {
        Write-Verbose "Get-EvidenceWindow: OS install date unreadable. $($_.Exception.Message)"
        $state = 'error'
    }

    try {
        $profileDir = Get-Item -LiteralPath $env:USERPROFILE -ErrorAction Stop
        $sources.Add([pscustomobject]@{ Name = 'profile-created'; Start = $profileDir.CreationTimeUtc })
    } catch {
        Write-Verbose "Get-EvidenceWindow: profile folder unreadable. $($_.Exception.Message)"
        $state = 'error'
    }

    $start = $null
    $days = $null
    if ($sources.Count -gt 0) {
        $start = ($sources | Sort-Object Start -Descending | Select-Object -First 1).Start
        $days = [int][math]::Floor(([datetime]::UtcNow - $start).TotalDays)
    }
    return [pscustomobject]@{ ReadState = $state; Start = $start; Days = $days; Sources = $sources.ToArray() }
}
