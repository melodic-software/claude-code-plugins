#Requires -Version 7.4

<#
.SYNOPSIS
Finds the earliest moment from which this user's launch records can be trusted
to be complete.

.DESCRIPTION
Returns { ReadState, Start }. Start is UTC, the later of the OS install date and
the user profile's creation time; launch records cannot predate either.

An input that cannot be read is left out and turns ReadState to error, since
Start may then be earlier than the records reach. Both missing leaves Start
$null.
#>

$script:OsVersionKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'

function Get-EvidenceWindow {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $starts = [System.Collections.Generic.List[datetime]]::new()
    $state = 'ok'

    try {
        $seconds = (Get-ItemProperty -LiteralPath $script:OsVersionKey -Name 'InstallDate' -ErrorAction Stop).InstallDate
        $starts.Add([DateTimeOffset]::FromUnixTimeSeconds([long]$seconds).UtcDateTime)
    } catch {
        Write-Verbose "Get-EvidenceWindow: OS install date unreadable. $($_.Exception.Message)"
        $state = 'error'
    }

    try {
        $starts.Add((Get-Item -LiteralPath $env:USERPROFILE -ErrorAction Stop).CreationTimeUtc)
    } catch {
        Write-Verbose "Get-EvidenceWindow: profile folder unreadable. $($_.Exception.Message)"
        $state = 'error'
    }

    $start = if ($starts.Count -gt 0) { ($starts | Measure-Object -Maximum).Maximum } else { $null }
    return [pscustomobject]@{ ReadState = $state; Start = $start }
}
