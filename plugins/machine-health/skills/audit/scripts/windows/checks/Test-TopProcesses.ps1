#Requires -Version 7.4
<#
.SYNOPSIS
Check: what is using this machine's CPU and memory over a short window. Emits a CheckResult JSON on stdout.

See reference/windows/check-catalog.md#26-top-processes for rubric.

.DESCRIPTION
Samples processes and system counters over -SampleSeconds (Get-ProcessSample)
and grades the system counters. The bands, their mapping to severity, the
sustained window and why the listed processes never raise severity are the
catalog section's decisions (see above). -SampleSeconds keeps a default for
direct runs; the orchestrator validates and passes the run's window.
#>
[CmdletBinding()]
param(
    [switch]$Human,
    [int]$SampleSeconds = 15,
    [string[]]$MutedKeys = @()
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\Write-HealthResult.ps1')
. (Join-Path $PSScriptRoot '..\lib\Get-ProcessSample.ps1')
. (Join-Path $PSScriptRoot '..\lib\New-FindingItem.ps1')

$id = 'top-processes'
$category = 'reliability'
$counter = $ProcessSampleCounter
$commands = @(
    "Get-Process (two snapshots $SampleSeconds s apart)"
    ("Get-Counter -Counter $(($counter.Paths.Values | ForEach-Object { "'$_'" }) -join ', ') " +
        "-SampleInterval $($counter.SampleInterval) -MaxSamples $SampleSeconds")
)
# The shortest window that grades disk latency (catalog section 26). The orchestrator's
# -SampleSeconds maximum must reach it; Get-CheckArgument.Tests.ps1 checks that.
$SustainedSeconds = 60

$FailureSummary = 'Top-processes sample failed.'
$PassThru = $false
$CheckBody = {
    $thresholdsLabel = 'Windows Server guidance (Microsoft Learn)'
    $topCount = 10
    # Values per band, keyed by the severity each reads as (mapping: catalog section 26).
    $band = @{
        CpuPct           = @{ INFO = 50; WARN = 80 }
        QueuePerCpu      = 2
        CommittedPct     = @{ INFO = 60; WARN = 80 }
        AvailablePctLow  = @{ INFO = 10; WARN = 1 }
        AvailableMbFloor = 500
        DiskMs           = @{ INFO = 25; WARN = 50 }
    }

    $sample = Get-ProcessSample -SampleSeconds $SampleSeconds
    $c = $sample.Counters
    $queuePerCpu = ($null -ne $c.ProcessorQueueLength) ?
        [math]::Round($c.ProcessorQueueLength / $sample.LogicalCpus, 2) : $null
    $availablePct = ($null -ne $c.AvailableMb -and $c.TotalPhysicalMb) ?
        [math]::Round($c.AvailableMb / $c.TotalPhysicalMb * 100, 1) : $null
    $sustained = $SampleSeconds -ge $SustainedSeconds

    $signals = [System.Collections.Generic.List[pscustomobject]]::new()
    $add = { param($metric, $level, $text) $signals.Add([pscustomobject]@{ metric = $metric; severity = $level; text = $text }) }

    if ($null -ne $c.CpuTotalPct) {
        if ($c.CpuTotalPct -ge $band.CpuPct.WARN) {
            & $add 'cpu_total_pct' 'WARN' "CPU $($c.CpuTotalPct)%"
        } elseif ($c.CpuTotalPct -ge $band.CpuPct.INFO) {
            $queueHigh = $null -ne $queuePerCpu -and $queuePerCpu -ge $band.QueuePerCpu
            & $add 'cpu_total_pct' ($queueHigh ? 'WARN' : 'INFO') (
                "CPU $($c.CpuTotalPct)%" + ($queueHigh ? " with $queuePerCpu queued per CPU" : ''))
        }
    }
    if ($null -ne $availablePct) {
        if ($availablePct -lt $band.AvailablePctLow.WARN -or $c.AvailableMb -lt $band.AvailableMbFloor) {
            & $add 'available_mb' 'WARN' "$($c.AvailableMb) MB memory available"
        } elseif ($availablePct -lt $band.AvailablePctLow.INFO) {
            & $add 'available_mb' 'INFO' "$availablePct% memory available"
        }
    }
    if ($null -ne $c.CommittedPct) {
        if ($c.CommittedPct -ge $band.CommittedPct.WARN) {
            & $add 'committed_pct' 'WARN' "$($c.CommittedPct)% committed"
        } elseif ($c.CommittedPct -ge $band.CommittedPct.INFO) {
            & $add 'committed_pct' 'INFO' "$($c.CommittedPct)% committed"
        }
    }
    if ($sustained -and $null -ne $c.DiskLatencyMs) {
        if ($c.DiskLatencyMs -gt $band.DiskMs.WARN) {
            & $add 'disk_latency_ms' 'WARN' "disk latency $($c.DiskLatencyMs) ms"
        } elseif ($c.DiskLatencyMs -gt $band.DiskMs.INFO) {
            & $add 'disk_latency_ms' 'INFO' "disk latency $($c.DiskLatencyMs) ms"
        }
    }

    $byCpu = @($sample.Processes | Where-Object { $null -ne $_.CpuPct } |
            Sort-Object -Property @{ Expression = 'CpuPct'; Descending = $true }, Name | Select-Object -First $topCount)
    $byMemory = @($sample.Processes | Sort-Object -Property @{ Expression = 'PrivateBytes'; Descending = $true }, Name |
            Select-Object -First $topCount)
    $seen = [System.Collections.Generic.HashSet[int]]::new()
    # Keyed by image file name, so a mute covers every instance of that program in every run.
    $items = @(foreach ($p in @($byCpu) + @($byMemory)) {
            if (-not $seen.Add($p.Id)) { continue }
            $image = $p.Path ? [System.IO.Path]::GetFileName($p.Path) : "$($p.Name).exe"
            New-FindingItem -Kind 'process' -Identity @($image.ToLowerInvariant()) -Severity 'OK' -Title $p.Name `
                -MutedKeys $MutedKeys -Fields @{
                    name           = $p.Name
                    path           = $p.Path
                    path_state     = $p.PathState
                    cpu_pct        = $p.CpuPct
                    private_mb     = [math]::Round($p.PrivateBytes / 1MB, 1)
                    working_set_mb = [math]::Round($p.WorkingSetBytes / 1MB, 1)
                }
        })

    $severity = Get-WorstSeverity -Levels @($signals | ForEach-Object severity)
    if ($severity -eq 'OK') { $severity = Get-UnmutedSeverity -ReadState $sample.ReadState }

    $diskNote = if (-not $sustained) {
        "disk latency not sustained-tested (window under $SustainedSeconds s)"
    } elseif ($null -ne $c.DiskLatencyMs) {
        "disk latency $($c.DiskLatencyMs) ms"
    }
    $window = "$($sample.IntervalSeconds) s on $($sample.LogicalCpus) CPUs"
    $lead = ($null -ne $c.CpuTotalPct) ? "CPU $($c.CpuTotalPct)% over $window" : "sampled $window"
    $unread = $sample.ReadState -ne 'ok' ? 'system counters unreadable' : $null
    $top = @($byCpu | Select-Object -First 3 | ForEach-Object { "$($_.Name) $($_.CpuPct)%" }) -join ', '
    $flagged = @($signals | Where-Object severity -NE 'OK' | ForEach-Object text) -join '; '
    $parts = @($lead, $unread, ($top ? "top: $top" : $null), ($flagged ? $flagged : $null), $diskNote,
        "bands: $thresholdsLabel") | Where-Object { $_ }
    $summary = ($parts -join '. ') + '.'
    if ($summary.Length -gt 240) { $summary = $summary.Substring(0, 237) + '...' }

    $detail = @{
        logical_cpus            = $sample.LogicalCpus
        sample_seconds          = $SampleSeconds
        interval_seconds        = $sample.IntervalSeconds
        cpu_total_pct           = $c.CpuTotalPct
        processor_queue_per_cpu = $queuePerCpu
        committed_pct           = $c.CommittedPct
        available_mb            = $c.AvailableMb
        available_pct           = $availablePct
        disk_latency_ms         = $c.DiskLatencyMs
        disk_latency_sustained  = $sustained
        counters_state          = $sample.ReadState
        thresholds_label        = $thresholdsLabel
        signals                 = @($signals)
        items                   = $items
        items_count             = $items.Count
        muted_count             = @($items | Where-Object muted).Count
    }

    $result = New-HealthResult -Id $id -Category $category -Os 'windows' -Severity $severity -Summary $summary `
        -Commands $commands -Detail $detail -NeedsAdmin $false -RanSuccessfully $true
}
. (Join-Path $PSScriptRoot '..\lib\Invoke-HealthCheckEnvelope.ps1')
