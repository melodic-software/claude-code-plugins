# Memory Diagnostics Reference

Comprehensive guide to memory diagnostics on Windows 11 using PowerShell.

## Overview

Memory diagnostics covers RAM usage analysis, identifying memory-hungry processes, detecting memory leaks, and checking for hardware memory errors.

## System Memory Overview

### Current Memory Status

```powershell
Get-CimInstance Win32_OperatingSystem | Select-Object `
    @{N='Total_GB';E={[math]::Round($_.TotalVisibleMemorySize/1MB,2)}},
    @{N='Free_GB';E={[math]::Round($_.FreePhysicalMemory/1MB,2)}},
    @{N='Used_GB';E={[math]::Round(($_.TotalVisibleMemorySize - $_.FreePhysicalMemory)/1MB,2)}},
    @{N='Used_Pct';E={[math]::Round((1 - $_.FreePhysicalMemory/$_.TotalVisibleMemorySize)*100,1)}},
    @{N='Virtual_Total_GB';E={[math]::Round($_.TotalVirtualMemorySize/1MB,2)}},
    @{N='Virtual_Free_GB';E={[math]::Round($_.FreeVirtualMemory/1MB,2)}}
```

### Physical Memory Details

```powershell
Get-CimInstance Win32_PhysicalMemory | Select-Object `
    BankLabel,
    DeviceLocator,
    @{N='Capacity_GB';E={[math]::Round($_.Capacity/1GB,2)}},
    Speed,
    Manufacturer,
    PartNumber
```

### Memory Slots

```powershell
# How many slots, how many used
$memory = Get-CimInstance Win32_PhysicalMemory
$slots = (Get-CimInstance Win32_PhysicalMemoryArray).MemoryDevices
[PSCustomObject]@{
    TotalSlots = $slots
    UsedSlots = $memory.Count
    TotalInstalled_GB = [math]::Round(($memory | Measure-Object Capacity -Sum).Sum/1GB,2)
}
```

## Process Memory Analysis

### Top Memory Consumers

```powershell
Get-Process | Sort-Object WorkingSet64 -Descending |
    Select-Object -First 15 ProcessName, Id,
        @{N='WS_MB';E={[math]::Round($_.WorkingSet64/1MB,0)}},
        @{N='PM_MB';E={[math]::Round($_.PrivateMemorySize64/1MB,0)}},
        @{N='VM_MB';E={[math]::Round($_.VirtualMemorySize64/1MB,0)}},
        HandleCount,
        @{N='Threads';E={$_.Threads.Count}}
```

### Memory Metrics Explained

| Metric | Property | Meaning |
| -------- | ---------- | --------- |
| Working Set | WorkingSet64 | Physical RAM currently used |
| Private Memory | PrivateMemorySize64 | Memory not shared with other processes |
| Virtual Memory | VirtualMemorySize64 | Total address space (physical + page file) |
| Paged Memory | PagedMemorySize64 | Memory that can be paged to disk |
| Non-Paged | NonpagedSystemMemorySize64 | Memory that must stay in RAM |

### Detailed Process Memory

```powershell
# Specific process details
Get-Process -Name chrome | Select-Object `
    Name, Id,
    @{N='WS_MB';E={[math]::Round($_.WorkingSet64/1MB,0)}},
    @{N='PM_MB';E={[math]::Round($_.PrivateMemorySize64/1MB,0)}},
    @{N='Paged_MB';E={[math]::Round($_.PagedMemorySize64/1MB,0)}},
    @{N='NonPaged_KB';E={[math]::Round($_.NonpagedSystemMemorySize64/1KB,0)}},
    HandleCount,
    @{N='StartTime';E={$_.StartTime}},
    @{N='CPU_Sec';E={[math]::Round($_.CPU,2)}}
```

### Group by Process Name

```powershell
# Total memory by application (useful for multi-process apps like Chrome)
Get-Process | Group-Object ProcessName | ForEach-Object {
    [PSCustomObject]@{
        Name = $_.Name
        Instances = $_.Count
        Total_MB = [math]::Round(($_.Group | Measure-Object WorkingSet64 -Sum).Sum/1MB,0)
    }
} | Sort-Object Total_MB -Descending | Select-Object -First 15
```

## Memory Leak Detection

### Signs of Memory Leaks

1. Memory usage grows over time without corresponding activity
2. Free memory continuously decreases
3. Specific process memory keeps increasing
4. System becomes slow after extended uptime

### Monitor Process Memory Over Time

```powershell
# Take a snapshot (run periodically to compare)
Get-Process | Where-Object { $_.WorkingSet64 -gt 100MB } |
    Select-Object ProcessName, Id,
        @{N='WS_MB';E={[math]::Round($_.WorkingSet64/1MB,0)}},
        @{N='Timestamp';E={Get-Date -Format 'yyyy-MM-dd HH:mm:ss'}} |
    Sort-Object WS_MB -Descending
```

### Performance Counters for Memory

```powershell
# Current memory metrics
Get-Counter -Counter @(
    '\Memory\Available MBytes',
    '\Memory\% Committed Bytes In Use',
    '\Memory\Pages/sec',
    '\Memory\Page Faults/sec',
    '\Memory\Pool Paged Bytes',
    '\Memory\Pool Nonpaged Bytes'
)
```

### Key Counters to Watch

| Counter | Warning Threshold | Meaning |
| --------- | ------------------- | --------- |
| Available MBytes | < 500 MB | Low free RAM |
| % Committed Bytes In Use | > 80% | High memory pressure |
| Pages/sec | > 1000 sustained | Excessive paging |
| Pool Nonpaged Bytes | Growing continuously | Possible driver leak |

## Page File Analysis

### Page File Configuration

```powershell
Get-CimInstance Win32_PageFileUsage | Select-Object `
    Name,
    @{N='AllocatedBase_MB';E={$_.AllocatedBaseSize}},
    @{N='CurrentUsage_MB';E={$_.CurrentUsage}},
    @{N='PeakUsage_MB';E={$_.PeakUsage}}
```

### Page File Settings

```powershell
Get-CimInstance Win32_PageFileSetting | Select-Object `
    Name,
    @{N='Initial_MB';E={$_.InitialSize}},
    @{N='Maximum_MB';E={$_.MaximumSize}}
```

## Windows Memory Diagnostic

### Check Previous Results

The Windows Memory Diagnostic tool runs at boot and logs results:

```powershell
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    ProviderName = 'Microsoft-Windows-MemoryDiagnostics-Results'
} -ErrorAction SilentlyContinue | Select-Object TimeCreated, Message
```

### Suggested: Schedule Memory Test

To run the Windows Memory Diagnostic (requires reboot):

```powershell
# This will prompt to reboot - USER SHOULD RUN MANUALLY
mdsched.exe
```

**Note:** This is a suggested command. Do not execute automatically as it requires a reboot.

## Memory-Related Events

### Query Memory Errors

```powershell
# Memory diagnostic results
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    ProviderName = 'Microsoft-Windows-MemoryDiagnostics-Results'
} -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Message

# WHEA memory errors
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    ProviderName = 'Microsoft-Windows-WHEA-Logger'
    StartTime = (Get-Date).AddDays(-30)
} -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -like '*memory*' } |
    Select-Object TimeCreated, Id, Message
```

### Resource Exhaustion Events

```powershell
# Low memory conditions
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    Id = 2004  # Resource exhaustion
    StartTime = (Get-Date).AddDays(-30)
} -MaxEvents 20 -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Message
```

## Committed Memory Analysis

### System Commit Charge

```powershell
# Commit charge (virtual memory commitment)
$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
[PSCustomObject]@{
    Physical_GB = [math]::Round($cs.TotalPhysicalMemory/1GB,2)
    CommitLimit_GB = [math]::Round(($os.TotalVirtualMemorySize*1KB)/1GB,2)
    CommitTotal_GB = [math]::Round((($os.TotalVirtualMemorySize - $os.FreeVirtualMemory)*1KB)/1GB,2)
    CommitPeak_GB = 'Check Task Manager' # Not easily available via WMI
}
```

## Quick Diagnostic Workflow

1. **Check current memory status:**

   ```powershell
   Get-CimInstance Win32_OperatingSystem | Select-Object @{N='Used%';E={[math]::Round((1-$_.FreePhysicalMemory/$_.TotalVisibleMemorySize)*100,1)}}
   ```

2. **Find top memory consumers:**

   ```powershell
   Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 ProcessName, @{N='MB';E={[math]::Round($_.WorkingSet64/1MB,0)}}
   ```

3. **Check for memory pressure:**

   ```powershell
   Get-Counter '\Memory\Available MBytes','\Memory\% Committed Bytes In Use'
   ```

4. **Check previous memory test results:**

   ```powershell
   Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-MemoryDiagnostics-Results'} -ErrorAction SilentlyContinue
   ```

5. **If hardware issues suspected, suggest:**
   - Run Windows Memory Diagnostic: `mdsched.exe`
   - Check RAM seating
   - Test with one stick at a time

## Warning Signs Requiring Action

| Finding | Severity | Recommended Action |
| --------- | ---------- | ------------------- |
| Available MB < 500 | High | Close applications, check for leaks |
| % Committed > 90% | High | Add RAM or increase page file |
| Pages/sec > 1000 sustained | High | Add RAM, reduce workload |
| Memory test failures | Critical | Replace faulty RAM module |
| Single process > 50% RAM | Medium | Investigate process, possible leak |
| Pool nonpaged growing | Medium | Driver or kernel issue, update drivers |

---

**Last Updated:** 2025-12-03
