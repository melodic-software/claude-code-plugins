#Requires -Version 7.4
<#
.SYNOPSIS
Check: Event Log critical errors + BSODs. Emits a CheckResult JSON on stdout.

See reference/windows/check-catalog.md#3-event-log-critical-errors--bsods for rubric.
#>
[CmdletBinding()]
param([switch]$Human)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\Write-HealthResult.ps1')

$id = 'event-log-errors'
$category = 'reliability'
$commands = @(
    "Get-WinEvent -FilterHashtable @{ LogName='System'; Level=1,2; StartTime=(Get-Date).AddDays(-7) }"
    "Get-WinEvent -FilterHashtable @{ LogName='System'; ProviderName='Microsoft-Windows-Kernel-Power'; Id=41 }"
)

$script:NoiseAllowlist = @(
    [pscustomobject]@{ Provider = 'Microsoft-Windows-DistributedCOM'; Id = 10016 }
)

function Test-IsNoiseEvent {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory = $true)] $Event)
    foreach ($rule in $script:NoiseAllowlist) {
        if ($Event.ProviderName -eq $rule.Provider -and [int]$Event.Id -eq [int]$rule.Id) {
            return $true
        }
    }
    return $false
}

$FailureSummary = 'Event log check failed.'
$PassThru = $false
$CheckBody = {
    $cutoff = (Get-Date).AddDays(-7)

    $events = @()
    try {
        $events = @(Get-WinEvent -FilterHashtable @{
                LogName   = 'System'
                Level     = 1, 2
                StartTime = $cutoff
            } -ErrorAction Stop)
    } catch {
        if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*' -and
            $_.Exception.Message -notmatch 'No events were found') {
            throw
        }
        Write-Verbose 'Test-EventLogErrors: no events matched query.'
    }

    $noiseEvents = [System.Collections.Generic.List[object]]::new()
    $signalEvents = [System.Collections.Generic.List[object]]::new()
    foreach ($e in $events) {
        if (Test-IsNoiseEvent -Event $e) { $noiseEvents.Add($e) } else { $signalEvents.Add($e) }
    }

    $bugCheckEvents = @($signalEvents | Where-Object {
            $_.ProviderName -in 'Microsoft-Windows-WER-SystemErrorReporting', 'Microsoft-Windows-Kernel-BugCheck' -or
            ($_.ProviderName -eq 'Microsoft-Windows-Kernel-Power' -and $_.Id -eq 41)
        })

    $diskSourceEvents = @($signalEvents | Where-Object {
            $_.ProviderName -match '(?i)^(disk|Ntfs|volmgr|partmgr)'
        })

    $grouped = $signalEvents |
        Group-Object -Property @{ Expression = { "$($_.ProviderName)/$($_.Id)" } } |
        Sort-Object Count -Descending |
        Select-Object -First 5 |
        ForEach-Object {
            $first = ($_.Group | Sort-Object TimeCreated | Select-Object -First 1).TimeCreated
            $last = ($_.Group | Sort-Object TimeCreated -Descending | Select-Object -First 1).TimeCreated
            [pscustomobject]@{
                provider_and_id = $_.Name
                count           = $_.Count
                first_seen      = $first ? $first.ToString('o') : $null
                last_seen       = $last ? $last.ToString('o') : $null
            }
        }

    $severity = 'OK'
    $summary = 'No Error/Critical events in System log over the last 7 days.'

    if ($bugCheckEvents.Count -gt 0) {
        $severity = 'CRIT'
        $summary = "$($bugCheckEvents.Count) BugCheck/Kernel-Power(41) event(s) in last 7 days."
    } elseif ($diskSourceEvents.Count -gt 0) {
        $severity = 'CRIT'
        $summary = "$($diskSourceEvents.Count) disk-source Error/Critical event(s) in last 7 days."
    } elseif ($signalEvents.Count -gt 0) {
        $maxRepeats = ($grouped | Measure-Object count -Maximum).Maximum
        if ($maxRepeats -gt 5) {
            $severity = 'WARN'
            $summary = ("$($signalEvents.Count) Error/Critical events in last 7 days; " +
                "top source repeats $maxRepeats times.")
        } else {
            $severity = 'INFO'
            $summary = "$($signalEvents.Count) Error/Critical events in last 7 days."
        }
    }

    $detail = @{
        window_days             = 7
        total_events            = $signalEvents.Count
        filtered_noise_count    = $noiseEvents.Count
        bugcheck_event_count    = $bugCheckEvents.Count
        disk_source_event_count = $diskSourceEvents.Count
        top_sources             = @($grouped)
    }

    $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
        -Severity $severity -Summary $summary -Detail $detail -Commands $commands `
        -NeedsAdmin $false -RanSuccessfully $true
}
. (Join-Path $PSScriptRoot '..\lib\Invoke-HealthCheckEnvelope.ps1')
