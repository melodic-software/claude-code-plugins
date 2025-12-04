# Crash Analysis Reference

Comprehensive guide to analyzing Windows crashes, BSODs, and application failures.

## Overview

Crash analysis covers Blue Screen of Death (BSOD) events, application crashes, system hangs, and memory dump analysis.

## BSOD (Blue Screen of Death)

### Check for Recent BSODs

```powershell
# Bugcheck events from Windows Error Reporting
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'
    Id = 1001
    StartTime = (Get-Date).AddDays(-30)
} -ErrorAction SilentlyContinue | Select-Object TimeCreated, Message
```

### Kernel Power Failures (Event 41)

Event 41 indicates the system rebooted without a clean shutdown:

```powershell
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    ProviderName = 'Microsoft-Windows-Kernel-Power'
    Id = 41
    StartTime = (Get-Date).AddDays(-30)
} -ErrorAction SilentlyContinue | ForEach-Object {
    [PSCustomObject]@{
        Time = $_.TimeCreated
        BugcheckCode = $_.Properties[0].Value
        PowerButtonTimestamp = $_.Properties[1].Value
        SleepInProgress = $_.Properties[3].Value
        Message = $_.Message.Substring(0, [Math]::Min(200, $_.Message.Length))
    }
}
```

**BugcheckCode interpretation:**

- 0 = Power loss or hard reset (no BSOD)
- Non-zero = BSOD occurred (code is the stop code)

## Minidump Files

### Location and Listing

```powershell
# Default minidump location
$minidumpPath = 'C:\Windows\Minidump'

# List minidump files
Get-ChildItem $minidumpPath -ErrorAction SilentlyContinue |
    Select-Object Name,
        @{N='Size_KB';E={[math]::Round($_.Length/1KB,1)}},
        LastWriteTime |
    Sort-Object LastWriteTime -Descending
```

### Full Memory Dump

```powershell
# Check for full memory dump
Get-Item 'C:\Windows\MEMORY.DMP' -ErrorAction SilentlyContinue |
    Select-Object Name,
        @{N='Size_GB';E={[math]::Round($_.Length/1GB,2)}},
        LastWriteTime
```

### Crash Dump Settings

```powershell
# Check current crash dump configuration
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' |
    Select-Object CrashDumpEnabled, DumpFile, MinidumpDir, Overwrite

# CrashDumpEnabled values:
# 0 = None
# 1 = Complete memory dump
# 2 = Kernel memory dump
# 3 = Small memory dump (minidump)
# 7 = Automatic memory dump
```

## Common BSOD Stop Codes

| Stop Code | Hex | Common Causes |
| ----------- | ----- | --------------- |
| KERNEL_DATA_INPAGE_ERROR | 0x7A | Disk failure, cable issues |
| PAGE_FAULT_IN_NONPAGED_AREA | 0x50 | Bad RAM, faulty driver |
| SYSTEM_SERVICE_EXCEPTION | 0x3B | Driver or software bug |
| DRIVER_IRQL_NOT_LESS_OR_EQUAL | 0xD1 | Bad driver |
| CRITICAL_PROCESS_DIED | 0xEF | Critical process crashed |
| WHEA_UNCORRECTABLE_ERROR | 0x124 | Hardware error (CPU, RAM, etc.) |
| VIDEO_TDR_FAILURE | 0x116 | GPU driver timeout |
| IRQL_NOT_LESS_OR_EQUAL | 0xA | Driver accessing wrong memory |
| KMODE_EXCEPTION_NOT_HANDLED | 0x1E | Kernel exception |
| SYSTEM_THREAD_EXCEPTION_NOT_HANDLED | 0x7E | System thread crashed |
| UNEXPECTED_KERNEL_MODE_TRAP | 0x7F | Hardware issue or overheating |
| KERNEL_SECURITY_CHECK_FAILURE | 0x139 | Security check failed, often memory corruption |
| BAD_POOL_HEADER | 0x19 | Memory pool corruption |
| BAD_POOL_CALLER | 0xC2 | Invalid pool request |
| DRIVER_OVERRAN_STACK_BUFFER | 0xF7 | Security vulnerability detected |

## Application Crashes

### Application Error Events

```powershell
# Application crashes (Event 1000)
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    ProviderName = 'Application Error'
    Id = 1000
    StartTime = (Get-Date).AddDays(-7)
} -MaxEvents 30 -ErrorAction SilentlyContinue |
    Select-Object TimeCreated,
        @{N='Application';E={$_.Properties[0].Value}},
        @{N='Version';E={$_.Properties[1].Value}},
        @{N='FaultModule';E={$_.Properties[3].Value}},
        @{N='ExceptionCode';E={'0x{0:X8}' -f $_.Properties[6].Value}}
```

### Application Hang Events

```powershell
# Application hangs (Event 1002)
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    ProviderName = 'Application Hang'
    Id = 1002
    StartTime = (Get-Date).AddDays(-7)
} -MaxEvents 20 -ErrorAction SilentlyContinue |
    Select-Object TimeCreated,
        @{N='Application';E={$_.Properties[0].Value}},
        @{N='Version';E={$_.Properties[1].Value}},
        @{N='HangType';E={$_.Properties[4].Value}}
```

## Windows Error Reporting

### WER Reports Location

```powershell
# Report queue
Get-ChildItem "$env:ProgramData\Microsoft\Windows\WER\ReportQueue" -Directory -ErrorAction SilentlyContinue |
    Select-Object Name, LastWriteTime |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 10

# Report archive
Get-ChildItem "$env:ProgramData\Microsoft\Windows\WER\ReportArchive" -Directory -ErrorAction SilentlyContinue |
    Select-Object Name, LastWriteTime |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 10
```

### Parse WER Report

```powershell
# Example: Read a WER report
$reportPath = (Get-ChildItem "$env:ProgramData\Microsoft\Windows\WER\ReportQueue" -Directory | Select-Object -First 1).FullName
if ($reportPath) {
    Get-Content "$reportPath\Report.wer" -ErrorAction SilentlyContinue | Select-Object -First 30
}
```

## Service Crashes

### Service Failure Events

```powershell
# Service Control Manager errors
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    ProviderName = 'Service Control Manager'
    Level = 1,2  # Critical, Error
    StartTime = (Get-Date).AddDays(-7)
} -MaxEvents 30 -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Id, Message
```

### Service-Specific Crashes

```powershell
# Find services that crashed
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    Id = 7031  # Service terminated unexpectedly
    StartTime = (Get-Date).AddDays(-7)
} -MaxEvents 20 -ErrorAction SilentlyContinue |
    Select-Object TimeCreated,
        @{N='Service';E={$_.Properties[0].Value}},
        Message
```

## Crash Timeline

### Build Comprehensive Timeline

```powershell
$events = @()

# Kernel power failures
$events += Get-WinEvent -FilterHashtable @{LogName='System';Id=41;StartTime=(Get-Date).AddDays(-30)} -ErrorAction SilentlyContinue |
    Select-Object @{N='Time';E={$_.TimeCreated}}, @{N='Type';E={'BSOD/Power'}}, @{N='Source';E={'Kernel-Power'}}

# Bugcheck events
$events += Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-WER-SystemErrorReporting';StartTime=(Get-Date).AddDays(-30)} -ErrorAction SilentlyContinue |
    Select-Object @{N='Time';E={$_.TimeCreated}}, @{N='Type';E={'Bugcheck'}}, @{N='Source';E={'WER'}}

# Application crashes
$events += Get-WinEvent -FilterHashtable @{LogName='Application';Id=1000;StartTime=(Get-Date).AddDays(-30)} -MaxEvents 50 -ErrorAction SilentlyContinue |
    Select-Object @{N='Time';E={$_.TimeCreated}}, @{N='Type';E={'App Crash'}}, @{N='Source';E={$_.Properties[0].Value}}

# Application hangs
$events += Get-WinEvent -FilterHashtable @{LogName='Application';Id=1002;StartTime=(Get-Date).AddDays(-30)} -MaxEvents 50 -ErrorAction SilentlyContinue |
    Select-Object @{N='Time';E={$_.TimeCreated}}, @{N='Type';E={'App Hang'}}, @{N='Source';E={$_.Properties[0].Value}}

# Service crashes
$events += Get-WinEvent -FilterHashtable @{LogName='System';Id=7031;StartTime=(Get-Date).AddDays(-30)} -MaxEvents 20 -ErrorAction SilentlyContinue |
    Select-Object @{N='Time';E={$_.TimeCreated}}, @{N='Type';E={'Service Crash'}}, @{N='Source';E={$_.Properties[0].Value}}

$events | Sort-Object Time -Descending | Select-Object -First 50
```

## Quick Diagnostic Workflow

1. **Check for recent BSODs:**

   ```powershell
   Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-WER-SystemErrorReporting'} -MaxEvents 10 -ErrorAction SilentlyContinue
   ```

2. **Check minidumps:**

   ```powershell
   Get-ChildItem C:\Windows\Minidump -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
   ```

3. **Check for unexpected shutdowns:**

   ```powershell
   Get-WinEvent -FilterHashtable @{LogName='System';Id=41;StartTime=(Get-Date).AddDays(-30)} -ErrorAction SilentlyContinue
   ```

4. **Check application crashes:**

   ```powershell
   Get-WinEvent -FilterHashtable @{LogName='Application';Id=1000,1002;StartTime=(Get-Date).AddDays(-7)} -MaxEvents 20 -ErrorAction SilentlyContinue
   ```

5. **Correlate timing:**
   - Same time pattern? (Check scheduled tasks, updates)
   - Same application? (Update or reinstall)
   - Same stop code? (Target specific component)
   - Random? (Hardware investigation needed)

## Dump Analysis Tools (User Runs)

### BlueScreenView (NirSoft)

Free, user-friendly BSOD analyzer:

- Download from: <https://www.nirsoft.net/utils/blue_screen_view.html>
- Automatically reads minidumps
- Shows crash details, driver involved
- No installation required

### WinDbg (Windows Debugger)

Professional crash dump analyzer:

```powershell
# Install via winget (if not installed)
# winget install Microsoft.WinDbg

# Basic analysis command
# windbg -z "C:\Windows\Minidump\filename.dmp" -c "!analyze -v; q"
```

### WhoCrashed

Automated crash analysis tool:

- Download from: <https://www.resplendence.com/whocrashed>
- Provides plain-English crash explanations
- Identifies likely driver causing crash

## Warning Signs Requiring Action

| Finding | Severity | Recommended Action |
| --------- | ---------- | ------------------- |
| Frequent Event 41 | Critical | Hardware investigation |
| Same BSOD stop code | High | Target specific component |
| WHEA_UNCORRECTABLE_ERROR | Critical | Hardware failing |
| Multiple minidumps | High | Analyze with BlueScreenView |
| Driver-related BSOD | Medium-High | Update/rollback driver |
| Specific app crashing | Medium | Update/reinstall app |
| Service crashes | Medium | Check service dependencies |

## Suggested Actions

**For recurring BSODs:**

1. Note the stop code from Event Viewer
2. Download BlueScreenView to analyze minidumps
3. Identify the driver/module involved
4. Update or rollback that driver
5. If hardware-related, run diagnostics

**For application crashes:**

1. Update the application
2. Check for Windows updates
3. Run `sfc /scannow` (user runs)
4. Reinstall if persistent

**For system instability:**

1. Run memory diagnostics (`mdsched.exe`)
2. Check disk health
3. Update all drivers
4. Consider clean Windows installation if severe

---

**Last Updated:** 2025-12-03
