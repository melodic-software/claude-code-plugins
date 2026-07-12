#Requires -Version 7.4
<#
.SYNOPSIS
Check: Event Log critical errors + BSODs. Emits a CheckResult JSON on stdout.

See references/windows/check-catalog.md#3-event-log-critical-errors--bsods for rubric.
#>
[CmdletBinding()]
param([switch]$Human)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\Write-HealthResult.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$id = 'event-log-errors'
$category = 'reliability'
$commands = @(
    "Get-WinEvent -LogName System -MaxEvents 500 | Where-Object { `$_.LevelDisplayName -in 'Error','Critical' }"
    "Get-WinEvent -FilterHashtable @{ LogName='System'; ProviderName='Microsoft-Windows-Kernel-Power'; Id=41 }"
)

# Benign-noise allowlist. Events matching these (Provider, Id) tuples are
# removed from the severity calculation entirely. DCOM 10016 is the
# canonical example -- every healthy Windows install logs it multiple
# times per day because the system is trying to touch a local COM
# server whose ACL doesn't include the calling identity. This is
# harmless and not actionable. The list stays deliberately conservative;
# per-host extensions belong in approvals.json check_overrides.
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

try {
    $cutoff = (Get-Date).AddDays(-7)

    $events = @()
    try {
        $events = Get-WinEvent -LogName System -MaxEvents 500 -ErrorAction Stop |
            Where-Object { $_.LevelDisplayName -in 'Error', 'Critical' }
    } catch {
        # Get-WinEvent throws a specific exception when no events match
        # the filter. Treat as empty result; re-throw anything else.
        if ($_.Exception.Message -notmatch 'No events were found') {
            throw
        }
        Write-Verbose 'Test-EventLogErrors: no events matched query.'
    }

    $windowEvents = @($events | Where-Object { $_.TimeCreated -ge $cutoff })

    $noiseEvents = @($windowEvents | Where-Object { Test-IsNoiseEvent -Event $_ })
    $signalEvents = @($windowEvents | Where-Object { -not (Test-IsNoiseEvent -Event $_) })

    $bugCheckEvents = @($signalEvents | Where-Object {
            $_.ProviderName -eq 'Microsoft-Windows-WER-SystemErrorReporting' -or
            $_.ProviderName -eq 'Microsoft-Windows-Kernel-BugCheck' -or
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
                first_seen      = if ($first) { $first.ToString('o') } else { $null }
                last_seen       = if ($last) { $last.ToString('o') } else { $null }
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
        -NeedsAdmin $false -RanSuccessfully $true -DurationMs ([int]$sw.ElapsedMilliseconds)
} catch {
    $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
        -Severity 'UNKNOWN' -Summary 'Event log check failed.' -Commands $commands `
        -RanSuccessfully $false -ErrorMessage $_.Exception.Message `
        -DurationMs ([int]$sw.ElapsedMilliseconds)
}

$sw.Stop()
$result.duration_ms = [int]$sw.ElapsedMilliseconds
$result | Write-HealthResult -Human:$Human
