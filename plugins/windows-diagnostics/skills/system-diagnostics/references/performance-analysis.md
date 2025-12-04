# Performance Analysis Reference

Comprehensive guide to Windows 11 performance diagnostics using PowerShell.

## Overview

Performance analysis covers CPU utilization, memory pressure, disk I/O, and network throughput to identify bottlenecks and resource-hungry processes.

## Performance Counters Overview

The `Get-Counter` cmdlet provides access to Windows Performance Counters.

### List Available Counter Sets

```powershell
# All counter sets
Get-Counter -ListSet * | Select-Object CounterSetName | Sort-Object CounterSetName

# Specific set details
Get-Counter -ListSet 'Processor' | Select-Object -ExpandProperty Counter
```

## CPU Analysis

### Current CPU Utilization

```powershell
# Overall CPU usage
Get-Counter -Counter '\Processor(_Total)\% Processor Time'

# Per-core usage
Get-Counter -Counter '\Processor(*)\% Processor Time' |
    Select-Object -ExpandProperty CounterSamples |
    Where-Object { $_.InstanceName -ne '_total' } |
    Select-Object InstanceName, @{N='CPU%';E={[math]::Round($_.CookedValue,1)}}
```

### CPU Over Time

```powershell
# 5 samples, 2 seconds apart
Get-Counter -Counter '\Processor(_Total)\% Processor Time' -SampleInterval 2 -MaxSamples 5 |
    ForEach-Object {
        [PSCustomObject]@{
            Time = $_.Timestamp
            CPU_Pct = [math]::Round($_.CounterSamples.CookedValue, 1)
        }
    }
```

### Top CPU Processes

```powershell
# By CPU time (cumulative)
Get-Process | Sort-Object CPU -Descending |
    Select-Object -First 10 ProcessName, Id,
        @{N='CPU_Sec';E={[math]::Round($_.CPU,2)}},
        @{N='WS_MB';E={[math]::Round($_.WorkingSet64/1MB,0)}}

# Current CPU usage by process (snapshot)
Get-Counter -Counter '\Process(*)\% Processor Time' |
    Select-Object -ExpandProperty CounterSamples |
    Where-Object { $_.CookedValue -gt 1 -and $_.InstanceName -notlike '*idle*' -and $_.InstanceName -ne '_total' } |
    Sort-Object CookedValue -Descending |
    Select-Object -First 10 InstanceName, @{N='CPU%';E={[math]::Round($_.CookedValue,1)}}
```

### CPU Queue Length

High queue length indicates CPU bottleneck:

```powershell
Get-Counter -Counter '\System\Processor Queue Length'
# > 2 per core suggests CPU bottleneck
```

## Memory Analysis

### Memory Counters

```powershell
Get-Counter -Counter @(
    '\Memory\Available MBytes',
    '\Memory\% Committed Bytes In Use',
    '\Memory\Pages/sec',
    '\Memory\Page Faults/sec',
    '\Memory\Pool Paged Bytes',
    '\Memory\Pool Nonpaged Bytes'
)
```

### Memory Pressure Indicators

| Counter | Warning Threshold | Meaning |
| --------- | ------------------- | --------- |
| Available MBytes | < 500 MB | Low free RAM |
| % Committed Bytes In Use | > 80% | High memory pressure |
| Pages/sec | > 1000 sustained | Excessive paging |
| Pool Nonpaged Bytes | Growing continuously | Possible driver leak |

### Top Memory Processes

```powershell
Get-Process | Sort-Object WorkingSet64 -Descending |
    Select-Object -First 15 ProcessName, Id,
        @{N='WS_MB';E={[math]::Round($_.WorkingSet64/1MB,0)}},
        @{N='PM_MB';E={[math]::Round($_.PrivateMemorySize64/1MB,0)}},
        HandleCount
```

### Memory by Application (Grouped)

```powershell
Get-Process | Group-Object ProcessName | ForEach-Object {
    [PSCustomObject]@{
        Name = $_.Name
        Instances = $_.Count
        Total_MB = [math]::Round(($_.Group | Measure-Object WorkingSet64 -Sum).Sum/1MB,0)
    }
} | Sort-Object Total_MB -Descending | Select-Object -First 15
```

## Disk I/O Analysis

### Disk Counters

```powershell
Get-Counter -Counter @(
    '\PhysicalDisk(_Total)\% Disk Time',
    '\PhysicalDisk(_Total)\Avg. Disk Queue Length',
    '\PhysicalDisk(_Total)\Disk Read Bytes/sec',
    '\PhysicalDisk(_Total)\Disk Write Bytes/sec',
    '\PhysicalDisk(_Total)\Avg. Disk sec/Read',
    '\PhysicalDisk(_Total)\Avg. Disk sec/Write'
)
```

### Disk Bottleneck Indicators

| Counter | Warning Threshold | Meaning |
| --------- | ------------------- | --------- |
| % Disk Time | > 80% sustained | Heavy disk usage |
| Avg. Disk Queue Length | > 2 per disk | Disk bottleneck |
| Avg. Disk sec/Read | > 0.020 (20ms) | Slow reads |
| Avg. Disk sec/Write | > 0.020 (20ms) | Slow writes |

### Per-Disk Stats

```powershell
Get-Counter -Counter '\PhysicalDisk(*)\% Disk Time' |
    Select-Object -ExpandProperty CounterSamples |
    Where-Object { $_.InstanceName -ne '_total' } |
    Select-Object InstanceName, @{N='Disk%';E={[math]::Round($_.CookedValue,1)}}
```

### Top Disk I/O Processes

```powershell
Get-Counter -Counter '\Process(*)\IO Read Bytes/sec', '\Process(*)\IO Write Bytes/sec' |
    Select-Object -ExpandProperty CounterSamples |
    Where-Object { $_.CookedValue -gt 1000 -and $_.InstanceName -ne '_total' } |
    Group-Object InstanceName |
    ForEach-Object {
        [PSCustomObject]@{
            Process = $_.Name
            Read_KBps = [math]::Round(($_.Group | Where-Object { $_.Path -like '*Read*' }).CookedValue/1KB, 1)
            Write_KBps = [math]::Round(($_.Group | Where-Object { $_.Path -like '*Write*' }).CookedValue/1KB, 1)
        }
    } | Sort-Object { $_.Read_KBps + $_.Write_KBps } -Descending | Select-Object -First 10
```

## Network Analysis

### Network Counters

```powershell
Get-Counter -Counter '\Network Interface(*)\Bytes Total/sec' |
    Select-Object -ExpandProperty CounterSamples |
    Where-Object { $_.CookedValue -gt 0 } |
    Select-Object InstanceName, @{N='MBps';E={[math]::Round($_.CookedValue/1MB,2)}}
```

### Network Adapter Stats

```powershell
Get-NetAdapterStatistics | Select-Object `
    Name,
    @{N='Sent_GB';E={[math]::Round($_.SentBytes/1GB,2)}},
    @{N='Recv_GB';E={[math]::Round($_.ReceivedBytes/1GB,2)}},
    OutboundDiscardedPackets,
    InboundDiscardedPackets,
    OutboundPacketErrors,
    InboundPacketErrors
```

### Top Network Processes (Connections)

```powershell
Get-NetTCPConnection -State Established |
    Group-Object OwningProcess |
    ForEach-Object {
        $proc = Get-Process -Id $_.Name -ErrorAction SilentlyContinue
        [PSCustomObject]@{
            Process = if($proc){$proc.ProcessName}else{'System'}
            PID = $_.Name
            Connections = $_.Count
        }
    } | Sort-Object Connections -Descending | Select-Object -First 10
```

## Comprehensive Performance Snapshot

```powershell
# All key metrics at once
$counters = Get-Counter -Counter @(
    '\Processor(_Total)\% Processor Time',
    '\Memory\Available MBytes',
    '\Memory\% Committed Bytes In Use',
    '\PhysicalDisk(_Total)\% Disk Time',
    '\PhysicalDisk(_Total)\Avg. Disk Queue Length',
    '\System\Processor Queue Length'
)

$samples = $counters.CounterSamples
[PSCustomObject]@{
    Timestamp = $counters.Timestamp
    CPU_Pct = [math]::Round(($samples | Where-Object { $_.Path -like '*Processor Time*' }).CookedValue, 1)
    RAM_Available_MB = [math]::Round(($samples | Where-Object { $_.Path -like '*Available MBytes*' }).CookedValue, 0)
    RAM_Committed_Pct = [math]::Round(($samples | Where-Object { $_.Path -like '*Committed*' }).CookedValue, 1)
    Disk_Pct = [math]::Round(($samples | Where-Object { $_.Path -like '*Disk Time*' }).CookedValue, 1)
    Disk_Queue = [math]::Round(($samples | Where-Object { $_.Path -like '*Queue Length*' -and $_.Path -like '*Disk*' }).CookedValue, 2)
    CPU_Queue = [math]::Round(($samples | Where-Object { $_.Path -like '*Processor Queue*' }).CookedValue, 0)
}
```

## Continuous Monitoring

### Real-Time Dashboard

```powershell
# 10 samples, 5 seconds apart
1..10 | ForEach-Object {
    $c = Get-Counter -Counter '\Processor(_Total)\% Processor Time','\Memory\Available MBytes','\PhysicalDisk(_Total)\% Disk Time'
    [PSCustomObject]@{
        Time = Get-Date -Format 'HH:mm:ss'
        CPU = [math]::Round($c.CounterSamples[0].CookedValue,0)
        RAM_Free_MB = [math]::Round($c.CounterSamples[1].CookedValue,0)
        Disk = [math]::Round($c.CounterSamples[2].CookedValue,0)
    }
    Start-Sleep -Seconds 5
}
```

## Performance Event Logs

### Slow Boot/Shutdown

```powershell
# Boot degradation events
Get-WinEvent -LogName 'Microsoft-Windows-Diagnostics-Performance/Operational' -MaxEvents 30 |
    Where-Object { $_.Id -in 100, 101, 102, 200, 201, 202 } |
    Select-Object TimeCreated, Id,
        @{N='Type';E={switch($_.Id){100{'Boot'};101{'App Delay'};102{'Driver Delay'};200{'Shutdown'};201{'App Delay'};202{'Service Delay'}}}},
        @{N='Duration_ms';E={$_.Properties[0].Value}}
```

### Resource Exhaustion

```powershell
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    Id = 2004  # Resource exhaustion
    StartTime = (Get-Date).AddDays(-30)
} -MaxEvents 20 -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Message
```

## Quick Diagnostic Workflow

1. **Quick system overview:**

   ```powershell
   Get-Counter '\Processor(_Total)\% Processor Time','\Memory\Available MBytes','\PhysicalDisk(_Total)\% Disk Time'
   ```

2. **Identify CPU hogs:**

   ```powershell
   Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 ProcessName, CPU
   ```

3. **Identify memory hogs:**

   ```powershell
   Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 5 ProcessName, @{N='MB';E={[math]::Round($_.WorkingSet64/1MB)}}
   ```

4. **Check for bottlenecks:**

   ```powershell
   Get-Counter '\System\Processor Queue Length','\PhysicalDisk(_Total)\Avg. Disk Queue Length','\Memory\Pages/sec'
   ```

5. **If bottleneck found:**
   - CPU: Identify and address high-CPU processes
   - Memory: Close apps, check for leaks, add RAM
   - Disk: Check disk health, consider SSD upgrade
   - Network: Check bandwidth, identify talkers

## Warning Signs Requiring Action

| Finding | Severity | Recommended Action |
| --------- | ---------- | ------------------- |
| CPU > 90% sustained | High | Identify process, throttle/stop |
| RAM Available < 500MB | High | Close apps, check for leaks |
| Disk > 80% sustained | Medium-High | Identify I/O source, check disk |
| Queue lengths > 2 | Medium | Resource bottleneck |
| Paging > 1000/sec | Medium | Add RAM |
| Boot time > 60s | Low-Medium | Check startup programs |

## Suggested Tools (User Runs)

```powershell
# Resource Monitor (GUI)
resmon

# Performance Monitor (GUI)
perfmon

# Task Manager (GUI)
taskmgr
```

---

**Last Updated:** 2025-12-03
