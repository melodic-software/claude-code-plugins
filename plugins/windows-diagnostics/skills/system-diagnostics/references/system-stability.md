# System Stability Reference

Comprehensive guide to analyzing Windows 11 system stability, uptime, and restart patterns.

## Overview

System stability analysis helps identify patterns in crashes, unexpected reboots, and system reliability issues.

## System Uptime

### Current Uptime

```powershell
# PowerShell 7+ native cmdlet
Get-Uptime                    # Returns TimeSpan since last boot
Get-Uptime -Since             # Returns DateTime of last boot
```

### Alternative Methods

```powershell
# Via CIM
(Get-CimInstance Win32_OperatingSystem).LastBootUpTime

# Calculate uptime manually
$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
$uptime = (Get-Date) - $boot
"System has been up for $($uptime.Days) days, $($uptime.Hours) hours, $($uptime.Minutes) minutes"
```

## Restart and Shutdown Events

### Key Event IDs

| Event ID | Provider | Meaning |
| ---------- | ---------- | --------- |
| 41 | Kernel-Power | Unexpected shutdown (kernel power failure) |
| 1074 | User32 | User/process initiated shutdown/restart |
| 1076 | User32 | Shutdown reason code |
| 6005 | EventLog | Event log service started (system boot) |
| 6006 | EventLog | Event log service stopped (clean shutdown) |
| 6008 | EventLog | Unexpected shutdown (dirty) |
| 6009 | EventLog | Windows version info at boot |
| 6013 | EventLog | System uptime |

### Query Restart Events

```powershell
# All restart-related events (last 30 days)
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    Id = 41, 1074, 6005, 6006, 6008
    StartTime = (Get-Date).AddDays(-30)
} | Select-Object TimeCreated, Id, ProviderName, Message |
    Sort-Object TimeCreated -Descending
```

### Unexpected Shutdowns (Critical)

```powershell
# Kernel-Power Event 41 = system rebooted without clean shutdown
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    ProviderName = 'Microsoft-Windows-Kernel-Power'
    Id = 41
    StartTime = (Get-Date).AddDays(-30)
} -ErrorAction SilentlyContinue | ForEach-Object {
    [PSCustomObject]@{
        Time = $_.TimeCreated
        EventId = $_.Id
        BugcheckCode = ($_.Properties[0].Value)
        Message = $_.Message
    }
}
```

**Bugcheck codes in Event 41:**

- 0 = Power loss or hard reset
- Non-zero = BSOD occurred

### User-Initiated Restarts

```powershell
# Event 1074 = shutdown/restart initiated by user or process
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    Id = 1074
    StartTime = (Get-Date).AddDays(-30)
} | ForEach-Object {
    [PSCustomObject]@{
        Time = $_.TimeCreated
        Process = $_.Properties[0].Value
        User = $_.Properties[6].Value
        Reason = $_.Properties[2].Value
        Comment = $_.Properties[5].Value
    }
}
```

### Dirty Shutdowns

```powershell
# Event 6008 = unexpected shutdown (prior boot was not clean)
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    Id = 6008
    StartTime = (Get-Date).AddDays(-30)
} -ErrorAction SilentlyContinue | Select-Object TimeCreated, Message
```

## Boot Performance

### Boot Time Analysis

```powershell
# Boot time from Diagnostics-Performance log
Get-WinEvent -LogName 'Microsoft-Windows-Diagnostics-Performance/Operational' -MaxEvents 50 |
    Where-Object { $_.Id -in 100, 101, 102 } |
    Select-Object TimeCreated, Id,
        @{N='Duration_ms';E={$_.Properties[0].Value}},
        Message
```

**Event IDs:**

- 100 = Windows started (includes boot time in ms)
- 101 = Application delayed boot
- 102 = Driver delayed boot

### Boot Degradation

```powershell
# Events indicating slow boot
Get-WinEvent -LogName 'Microsoft-Windows-Diagnostics-Performance/Operational' |
    Where-Object { $_.Id -in 101, 102, 103, 109 } |
    Select-Object TimeCreated, Id,
        @{N='Name';E={$_.Properties[4].Value}},
        @{N='Path';E={$_.Properties[5].Value}},
        @{N='Duration_ms';E={$_.Properties[0].Value}}
```

## Reliability Monitor Data

### Reliability History

The Reliability Monitor uses scheduled task data collection:

```powershell
# Check if reliability data collection is running
Get-ScheduledTask -TaskPath '\Microsoft\Windows\RAC\' -TaskName 'RacTask' -ErrorAction SilentlyContinue |
    Select-Object TaskName, State
```

### Query Reliability Metrics

```powershell
# Stability index (may not be available on all systems)
Get-CimInstance -Namespace root\cimv2 -ClassName Win32_ReliabilityStabilityMetrics -ErrorAction SilentlyContinue |
    Select-Object -First 10 TimeGenerated, SystemStabilityIndex |
    Sort-Object TimeGenerated -Descending
```

**Note:** Reliability Monitor is more reliably accessed via `perfmon /rel` GUI.

## BSOD (Blue Screen) Analysis

### Bugcheck Events

```powershell
# BSOD events from Windows Error Reporting
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'
    Id = 1001
    StartTime = (Get-Date).AddDays(-30)
} -ErrorAction SilentlyContinue | Select-Object TimeCreated, Message
```

### Minidump Files

```powershell
# List minidump files
Get-ChildItem C:\Windows\Minidump -ErrorAction SilentlyContinue |
    Select-Object Name, Length, LastWriteTime |
    Sort-Object LastWriteTime -Descending

# Check for full memory dump
Get-Item C:\Windows\MEMORY.DMP -ErrorAction SilentlyContinue |
    Select-Object Name, Length, LastWriteTime
```

### Common BSOD Stop Codes

| Stop Code | Meaning | Common Causes |
| ----------- | --------- | --------------- |
| KERNEL_DATA_INPAGE_ERROR | Can't read from disk | Disk failure, cable |
| PAGE_FAULT_IN_NONPAGED_AREA | Memory access error | Bad RAM, driver |
| SYSTEM_SERVICE_EXCEPTION | System service crashed | Driver, software |
| DRIVER_IRQL_NOT_LESS_OR_EQUAL | Driver memory violation | Bad driver |
| CRITICAL_PROCESS_DIED | Critical process crashed | Corruption, malware |
| WHEA_UNCORRECTABLE_ERROR | Hardware error | CPU, RAM, motherboard |
| VIDEO_TDR_FAILURE | Graphics driver timeout | GPU driver |

## Crash Timeline

### Build Crash Timeline

```powershell
# Comprehensive crash/restart timeline
$events = @()

# Kernel power failures
$events += Get-WinEvent -FilterHashtable @{LogName='System';Id=41;StartTime=(Get-Date).AddDays(-30)} -ErrorAction SilentlyContinue |
    Select-Object @{N='Time';E={$_.TimeCreated}}, @{N='Type';E={'Kernel Power Failure'}}, @{N='Details';E={$_.Message}}

# Unexpected shutdowns
$events += Get-WinEvent -FilterHashtable @{LogName='System';Id=6008;StartTime=(Get-Date).AddDays(-30)} -ErrorAction SilentlyContinue |
    Select-Object @{N='Time';E={$_.TimeCreated}}, @{N='Type';E={'Unexpected Shutdown'}}, @{N='Details';E={$_.Message}}

# BSOD events
$events += Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-WER-SystemErrorReporting';StartTime=(Get-Date).AddDays(-30)} -ErrorAction SilentlyContinue |
    Select-Object @{N='Time';E={$_.TimeCreated}}, @{N='Type';E={'BSOD/Bugcheck'}}, @{N='Details';E={$_.Message}}

# Sort by time
$events | Sort-Object Time -Descending | Format-Table -Wrap
```

## Sleep/Hibernate Issues

### Power State Events

```powershell
# Sleep/wake events
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    ProviderName = 'Microsoft-Windows-Kernel-Power'
    StartTime = (Get-Date).AddDays(-7)
} -MaxEvents 50 | Where-Object { $_.Id -in 42, 107, 507 } |
    Select-Object TimeCreated, Id, Message
```

**Event IDs:**

- 42 = System entering sleep
- 107 = System resumed from sleep
- 507 = Unable to sleep (something prevented it)

### Wake Reasons

```powershell
# What woke the system
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    ProviderName = 'Microsoft-Windows-Power-Troubleshooter'
    StartTime = (Get-Date).AddDays(-7)
} -ErrorAction SilentlyContinue | Select-Object TimeCreated, Message
```

## Quick Diagnostic Workflow

1. **Check uptime:**

   ```powershell
   Get-Uptime
   ```

2. **Recent unexpected shutdowns:**

   ```powershell
   Get-WinEvent -FilterHashtable @{LogName='System';Id=41,6008;StartTime=(Get-Date).AddDays(-30)} | Select-Object TimeCreated, Id, Message
   ```

3. **Check for BSOD events:**

   ```powershell
   Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-WER-SystemErrorReporting'} -MaxEvents 10 -ErrorAction SilentlyContinue
   ```

4. **Check minidumps:**

   ```powershell
   Get-ChildItem C:\Windows\Minidump -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
   ```

5. **If pattern emerges:**
   - Same time daily? Check scheduled tasks
   - After specific action? Check related drivers/apps
   - Random? Check hardware (RAM, disk, PSU)

## Warning Signs Requiring Action

| Finding | Severity | Recommended Action |
| --------- | ---------- | ------------------- |
| Multiple Event 41 | High | Hardware investigation needed |
| Event 6008 frequent | High | Check for power/hardware issues |
| Same BSOD stop code | High | Target specific component |
| Short uptime pattern | Medium | Investigate cause before next crash |
| Minidumps present | Medium | Analyze with WinDbg or BlueScreenView |
| Sleep failures | Low-Medium | Check wake sources, drivers |

## Suggested Tools for Analysis

For dump file analysis (user runs manually):

- **BlueScreenView (NirSoft):** User-friendly BSOD analyzer
- **WinDbg (Windows SDK):** Professional crash analyzer
- **WhoCrashed:** Automated crash analysis

```powershell
# Example: Open Reliability Monitor (GUI)
perfmon /rel
```

---

**Last Updated:** 2025-12-03
