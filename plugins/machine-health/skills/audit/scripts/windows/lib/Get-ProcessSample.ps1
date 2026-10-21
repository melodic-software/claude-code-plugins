#Requires -Version 7.4

<#
.SYNOPSIS
Sample per-process CPU share and system-wide performance counters over one window.

.DESCRIPTION
Takes two Get-Process snapshots -SampleSeconds apart. A process's CPU share is
its processor-time delta over (measured interval x logical CPUs) x 100, so a
process that keeps one of four CPUs busy reads 25. A process absent from the
first snapshot started inside the window, so all of its processor time counts.
Snapshots join on Id plus start time, so a reused process id never yields a
delta against an unrelated process.

The system-wide counters are read with Get-Counter during the window, between
the two snapshots, so the call takes about -SampleSeconds plus snapshot cost.
Only system counters are read: the per-process counter set errors
intermittently when processes come and go. Counter paths are English; on another
display language the read fails and ReadState is 'error'.

Returns:
  IntervalSeconds  measured seconds between the snapshots
  LogicalCpus      Win32_ComputerSystem NumberOfLogicalProcessors, else
                   [Environment]::ProcessorCount
  Processes        Name, Id, CpuPct (null when processor time is unreadable),
                   WorkingSetBytes, PrivateBytes, Path, PathState (ReadState)
  Counters         CpuTotalPct, ProcessorQueueLength, CommittedPct, AvailableMb,
                   TotalPhysicalMb, DiskLatencyMs (median per-second sample of the
                   slower of read and write), each null when unread
  ReadState        'ok' when every counter read, else 'error'
#>

function Get-ProcessSample {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [ValidateRange(1, 3600)] [int] $SampleSeconds = 15
    )

    $counterPaths = [ordered]@{
        CpuTotalPct          = '\Processor(_Total)\% Processor Time'
        ProcessorQueueLength = '\System\Processor Queue Length'
        CommittedPct         = '\Memory\% Committed Bytes In Use'
        AvailableMb          = '\Memory\Available MBytes'
        DiskReadSec          = '\PhysicalDisk(_Total)\Avg. Disk sec/Read'
        DiskWriteSec         = '\PhysicalDisk(_Total)\Avg. Disk sec/Write'
    }

    $first = Get-ProcessSnapshot
    $startedAt = Get-Date
    $sets = @(Get-Counter -Counter @($counterPaths.Values) -SampleInterval 1 -MaxSamples $SampleSeconds `
            -ErrorAction SilentlyContinue)
    # A counter read that fails early still leaves the CPU deltas a full window.
    $remainingMs = [int]($SampleSeconds * 1000 - ((Get-Date) - $startedAt).TotalMilliseconds)
    if ($remainingMs -gt 0) { Start-Sleep -Milliseconds $remainingMs }
    $second = Get-ProcessSnapshot

    $interval = ((Get-Date) - $startedAt).TotalSeconds
    $system = try { Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop } catch { $null }
    $logicalCpus = $system ? [int]$system.NumberOfLogicalProcessors : [Environment]::ProcessorCount
    $before = @{}
    foreach ($p in $first) { $before[$p.JoinKey] = $p }

    $processes = foreach ($p in $second) {
        $cpuPct = $null
        if ($null -ne $p.CpuSeconds) {
            $start = $before.ContainsKey($p.JoinKey) ? $before[$p.JoinKey].CpuSeconds : 0.0
            if ($null -ne $start) {
                $cpuPct = [math]::Round(($p.CpuSeconds - $start) / ($interval * $logicalCpus) * 100, 1)
            }
        }
        [pscustomobject]@{
            Name            = $p.Name
            Id              = $p.Id
            CpuPct          = $cpuPct
            WorkingSetBytes = $p.WorkingSetBytes
            PrivateBytes    = $p.PrivateBytes
            Path            = $p.Path
            PathState       = $p.PathState
        }
    }

    $series = @{}
    foreach ($name in $counterPaths.Keys) { $series[$name] = [System.Collections.Generic.List[double]]::new() }
    foreach ($set in $sets) {
        foreach ($s in @($set.CounterSamples)) {
            if ($s.Status -ne 0) { continue }
            foreach ($name in $counterPaths.Keys) {
                if ($s.Path.EndsWith($counterPaths[$name], [StringComparison]::OrdinalIgnoreCase)) {
                    $series[$name].Add([double]$s.CookedValue)
                }
            }
        }
    }
    $average = {
        param($values)
        if ($values.Count -eq 0) { return $null }
        [math]::Round(($values | Measure-Object -Average).Average, 2)
    }

    $diskMs = [System.Collections.Generic.List[double]]::new()
    $pairs = [math]::Min($series.DiskReadSec.Count, $series.DiskWriteSec.Count)
    for ($i = 0; $i -lt $pairs; $i++) {
        $diskMs.Add([math]::Max($series.DiskReadSec[$i], $series.DiskWriteSec[$i]) * 1000)
    }
    $diskLatency = $null
    if ($diskMs.Count -gt 0) {
        $sorted = @($diskMs | Sort-Object)
        $mid = [int][math]::Floor($sorted.Count / 2)
        $median = ($sorted.Count % 2) ? $sorted[$mid] : ($sorted[$mid - 1] + $sorted[$mid]) / 2
        $diskLatency = [math]::Round($median, 1)
    }

    $totalMb = $system ? [math]::Round($system.TotalPhysicalMemory / 1MB) : $null

    $counters = [pscustomobject]@{
        CpuTotalPct          = & $average $series.CpuTotalPct
        ProcessorQueueLength = & $average $series.ProcessorQueueLength
        CommittedPct         = & $average $series.CommittedPct
        AvailableMb          = & $average $series.AvailableMb
        TotalPhysicalMb      = $totalMb
        DiskLatencyMs        = $diskLatency
    }
    $unread = @($counters.PSObject.Properties | Where-Object { $null -eq $_.Value })

    return [pscustomobject]@{
        IntervalSeconds = [math]::Round($interval, 2)
        LogicalCpus     = $logicalCpus
        Processes       = @($processes)
        Counters        = $counters
        ReadState       = $unread.Count -eq 0 ? 'ok' : 'error'
    }
}

function Get-ProcessSnapshot {
    <#
    .SYNOPSIS
    One Get-Process pass reduced to plain values. Processor time and start time
    are null where the process denies the read.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) {
        # Id 0 is the Idle pseudo-process: its "CPU" is the unused capacity.
        if ($p.Id -eq 0) { continue }
        $cpu = try { $p.TotalProcessorTime.TotalSeconds } catch { $null }
        $start = try { $p.StartTime.ToUniversalTime().Ticks } catch { $null }
        $path = $p.Path
        # Id 4 (System) has no image file; any other process with no readable
        # path is taken as one that denies the read.
        $pathState = if ($path) { 'ok' } elseif ($p.Id -le 4) { 'absent' } else { 'denied' }
        [pscustomobject]@{
            Name            = $p.ProcessName
            Id              = $p.Id
            JoinKey         = "$($p.Id)|$($p.ProcessName)|$start"
            CpuSeconds      = $cpu
            WorkingSetBytes = [long]$p.WorkingSet64
            PrivateBytes    = [long]$p.PrivateMemorySize64
            Path            = $path ? $path : $null
            PathState       = $pathState
        }
    }
}
