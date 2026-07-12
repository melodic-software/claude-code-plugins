#Requires -Version 7.4
<#
.SYNOPSIS
Check: Reliability Monitor stability index + recent records. Emits a CheckResult JSON on stdout.

See references/windows/check-catalog.md#9-reliability-monitor for rubric.
#>
[CmdletBinding()]
param([switch]$Human)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\Write-HealthResult.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$id = 'reliability'
$category = 'reliability'
$commands = @(
    'Get-CimInstance Win32_ReliabilityStabilityMetrics | Sort-Object TimeGenerated -Descending | Select-Object -First 7'
    "Get-CimInstance Win32_ReliabilityRecords -Filter `"TimeGenerated > '<7d ago>'`""
)

try {
    # Win32_ReliabilityStabilityMetrics returns one row per day with a
    # SystemStabilityIndex in 0-10 (10 = most stable). Not deprecated on
    # Windows 11 26200, but the RAC (Reliability Analysis Component) task
    # must be running for the table to populate. When it isn't, we emit
    # INFO rather than UNKNOWN so the check doesn't cry wolf.
    $metrics = @()
    try {
        $metrics = @(Get-CimInstance -ClassName Win32_ReliabilityStabilityMetrics -ErrorAction Stop |
                Sort-Object TimeGenerated -Descending |
                Select-Object -First 7)
    } catch {
        Write-Verbose ('Test-Reliability: stability metrics query failed. ' + $_.Exception.Message)
    }

    $records = @()
    try {
        $cutoff = (Get-Date).AddDays(-7)
        $records = @(Get-CimInstance -ClassName Win32_ReliabilityRecords -ErrorAction Stop |
                Where-Object { $_.TimeGenerated -and $_.TimeGenerated -ge $cutoff })
    } catch {
        Write-Verbose ('Test-Reliability: records query failed. ' + $_.Exception.Message)
    }

    if ($metrics.Count -eq 0 -and $records.Count -eq 0) {
        # Either RAC task disabled or host is too new (< 7 days of data).
        $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
            -Severity 'INFO' `
            -Summary 'Reliability Monitor data not populated (RAC task may be disabled).' `
            -Detail @{
            stability_days   = 0
            records_count    = 0
            stability_min_7d = $null
            stability_avg_7d = $null
        } -Commands $commands `
            -NeedsAdmin $false -RanSuccessfully $true `
            -DurationMs ([int]$sw.ElapsedMilliseconds) `
            -Notes 'To enable: schtasks /Run /TN "\Microsoft\Windows\RAC\RacTask".'
    } else {
        $stabilityIndices = @($metrics | Where-Object { $null -ne $_.SystemStabilityIndex } |
                ForEach-Object { [double]$_.SystemStabilityIndex })
        $stabilityMin = $null
        $stabilityAvg = $null
        if ($stabilityIndices.Count -gt 0) {
            $stabilityMin = [math]::Round(($stabilityIndices | Measure-Object -Minimum).Minimum, 2)
            $stabilityAvg = [math]::Round(($stabilityIndices | Measure-Object -Average).Average, 2)
        }

        # Group records by SourceName + EventIdentifier for the top-N report.
        $topEvents = @($records | Group-Object -Property SourceName, EventIdentifier |
                Sort-Object Count -Descending | Select-Object -First 5 |
                ForEach-Object {
                    $sample = $_.Group[0]
                    [pscustomobject]@{
                        source           = $sample.SourceName
                        event_identifier = [int]$sample.EventIdentifier
                        count            = $_.Count
                        product_name     = $sample.ProductName
                    }
                })

        # Hardware/driver-class classifier: match on SourceName, which is a
        # structured provider identifier (e.g., "Disk", "Microsoft-Windows-Kernel-Power",
        # "Microsoft-Windows-WER-SystemErrorReporting"). Matching ProductName
        # instead would be too broad -- it is the crashing app's display name,
        # so ordinary Windows-component records (e.g., "Windows Explorer" hang
        # with ProductName="Windows") would be misclassified as hardware
        # failures, producing false CRIT reports.
        $hardwareCrashCount = @($records | Where-Object {
                $_.SourceName -match 'hardware|disk|memory|bugcheck|kernel-power|WER-SystemErrorReporting'
            }).Count

        # Same product crashing >=5 times in last 7 days is a WARN signal.
        $repeatCrashCount = 0
        if ($records.Count -gt 0) {
            $repeatCrashCount = @($records |
                    Group-Object -Property ProductName |
                    Where-Object { $_.Count -ge 5 }).Count
        }

        $severity = 'OK'
        $summary = "Stability avg $stabilityAvg / 10, $($records.Count) event(s) in 7d."
        if ($null -ne $stabilityMin -and $stabilityMin -lt 3) {
            $severity = 'CRIT'
            $summary = "Stability dropped below 3 (min $stabilityMin) in last 7d."
        } elseif ($hardwareCrashCount -gt 0) {
            $severity = 'CRIT'
            $summary = "$hardwareCrashCount hardware/driver failure record(s) in last 7d."
        } elseif ($null -ne $stabilityAvg -and $stabilityAvg -lt 7) {
            $severity = 'WARN'
            $summary = "Stability avg $stabilityAvg / 10 (threshold 7) in last 7d."
        } elseif ($repeatCrashCount -gt 0) {
            $severity = 'WARN'
            $summary = "$repeatCrashCount application(s) crashed >=5 times in last 7d."
        } elseif ($records.Count -gt 0) {
            $severity = 'INFO'
            $summary = "$($records.Count) event(s) in last 7d, stability avg $stabilityAvg."
        }

        $detail = @{
            stability_days      = $metrics.Count
            stability_min_7d    = $stabilityMin
            stability_avg_7d    = $stabilityAvg
            records_count       = $records.Count
            hardware_crash_count = $hardwareCrashCount
            repeat_crash_count  = $repeatCrashCount
            top_events          = $topEvents
        }

        $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
            -Severity $severity -Summary $summary -Detail $detail -Commands $commands `
            -NeedsAdmin $false -RanSuccessfully $true `
            -DurationMs ([int]$sw.ElapsedMilliseconds)
    }
} catch {
    $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
        -Severity 'UNKNOWN' -Summary 'Reliability check failed.' -Commands $commands `
        -RanSuccessfully $false -ErrorMessage $_.Exception.Message `
        -DurationMs ([int]$sw.ElapsedMilliseconds)
}

$sw.Stop()
$result.duration_ms = [int]$sw.ElapsedMilliseconds
$result | Write-HealthResult -Human:$Human
