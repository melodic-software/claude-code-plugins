#Requires -Version 7.4
<#
.SYNOPSIS
Check: what is using this machine's CPU and memory over a short window. Emits a CheckResult JSON on stdout.

See reference/windows/check-catalog.md#26-top-processes for rubric.

.DESCRIPTION
Samples processes and system counters over -SampleSeconds (Get-ProcessSample)
and grades the system counters against Microsoft Learn's published bands. Those
bands are written for Windows Server, and the result says so. Disk latency is
graded only when the window is long enough to call it sustained. The listed
processes are context: they never raise the severity, and a muted one stays
listed with muted = $true.
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
$commands = @(
    "Get-Process (two snapshots $SampleSeconds s apart)"
    "Get-Counter -Counter '\Processor(_Total)\% Processor Time', '\System\Processor Queue Length', '\Memory\% Committed Bytes In Use', '\Memory\Available MBytes', '\PhysicalDisk(_Total)\Avg. Disk sec/Read', '\PhysicalDisk(_Total)\Avg. Disk sec/Write' -SampleInterval 1 -MaxSamples $SampleSeconds"
)

$FailureSummary = 'Top-processes sample failed.'
$PassThru = $false
$CheckBody = {
    $thresholdsLabel = 'Windows Server guidance (Microsoft Learn)'
    # Learn's disk-latency guidance tolerates spikes and asks for latency sustained over about a minute.
    $sustainedSeconds = 60
    $topCount = 10
    # Learn's Warning band reads INFO and its Critical band WARN: a window of seconds on a
    # client is evidence to look at, not the imminent failure the rubric keeps CRIT for.
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
    $sustained = $SampleSeconds -ge $sustainedSeconds

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

    $floor = switch ($sample.ReadState) {
        'ok' { 'OK' }
        'absent' { 'OK' }
        default { 'UNKNOWN' }
    }
    $severity = Get-WorstSeverity -Levels (@(Get-UnmutedSeverity -Items $items) + @($signals | ForEach-Object severity))
    if ($floor -ne 'OK' -and $severity -eq 'OK') { $severity = $floor }

    $diskNote = $sustained ? "disk latency $($c.DiskLatencyMs) ms" :
        "disk latency not sustained-tested (window under $sustainedSeconds s)"
    $lead = "CPU $($c.CpuTotalPct)% over $($sample.IntervalSeconds) s on $($sample.LogicalCpus) CPUs"
    $top = @($byCpu | Select-Object -First 3 | ForEach-Object { "$($_.Name) $($_.CpuPct)%" }) -join ', '
    $flagged = @($signals | Where-Object severity -NE 'OK' | ForEach-Object text) -join '; '
    $parts = @($lead, ($top ? "top: $top" : $null), ($flagged ? $flagged : $null), $diskNote,
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
