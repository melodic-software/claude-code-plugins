# Event Logs Reference

Comprehensive guide to Windows Event Viewer analysis using PowerShell.

## Overview

Windows Event Logs are the primary source for diagnosing system issues. The `Get-WinEvent` cmdlet provides powerful filtering and analysis capabilities.

## Key Event Logs

| Log Name | Purpose | Admin Required |
| ---------- | --------- | ---------------- |
| System | OS events, drivers, hardware | No |
| Application | Application crashes, errors | No |
| Security | Logon, audit events | Yes |
| Setup | Windows updates, installs | No |

## Event Levels

| Level | Value | Meaning |
| ------- | ------- | --------- |
| Critical | 1 | Severe failure, system crash |
| Error | 2 | Significant problem |
| Warning | 3 | Potential issue |
| Information | 4 | Normal operation |
| Verbose | 5 | Detailed diagnostic info |

## Basic Queries

### Recent Critical and Error Events

```powershell
# System log - critical and errors (last 7 days)
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    Level = 1,2
    StartTime = (Get-Date).AddDays(-7)
} -MaxEvents 50 | Select-Object TimeCreated, Id, ProviderName, LevelDisplayName, Message

# Application log - same filter
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    Level = 1,2
    StartTime = (Get-Date).AddDays(-7)
} -MaxEvents 50 | Select-Object TimeCreated, Id, ProviderName, LevelDisplayName, Message
```

### Multiple Logs at Once

```powershell
Get-WinEvent -FilterHashtable @{
    LogName = 'System','Application'
    Level = 1,2,3
    StartTime = (Get-Date).AddDays(-7)
} -MaxEvents 100 | Sort-Object TimeCreated -Descending |
    Select-Object TimeCreated, LogName, Id, ProviderName, LevelDisplayName, Message
```

## Critical Event IDs for Diagnostics

### System Crashes and Reboots

| Event ID | Provider | Meaning |
| ---------- | ---------- | --------- |
| 41 | Kernel-Power | Unexpected shutdown (no clean shutdown) |
| 1074 | User32 | User/process initiated shutdown/restart |
| 6006 | EventLog | Clean shutdown |
| 6008 | EventLog | Unexpected shutdown (dirty) |
| 1001 | WER-SystemErrorReporting | Bugcheck/BSOD |

```powershell
# Query restart-related events
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    Id = 41, 1074, 6006, 6008, 1001
    StartTime = (Get-Date).AddDays(-30)
} | Select-Object TimeCreated, Id, ProviderName, Message | Sort-Object TimeCreated -Descending
```

### Disk Errors

| Event ID | Provider | Meaning |
| ---------- | ---------- | --------- |
| 7 | disk | Bad block detected |
| 11 | disk | Controller error |
| 15 | disk | Device not ready |
| 51 | disk | Paging error |
| 55 | ntfs | Filesystem corruption |
| 137 | ntfs | Volume dirty |

```powershell
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    ProviderName = 'disk', 'ntfs'
    StartTime = (Get-Date).AddDays(-30)
} -MaxEvents 50 | Select-Object TimeCreated, Id, ProviderName, Message
```

### Hardware Errors (WHEA)

```powershell
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    ProviderName = 'Microsoft-Windows-WHEA-Logger'
    StartTime = (Get-Date).AddDays(-30)
} -MaxEvents 50 -ErrorAction SilentlyContinue | Select-Object TimeCreated, Id, Message
```

### Application Crashes

| Event ID | Provider | Meaning |
| ---------- | ---------- | --------- |
| 1000 | Application Error | Application crash |
| 1001 | Windows Error Reporting | Crash details |
| 1002 | Application Hang | Application not responding |

```powershell
Get-WinEvent -FilterHashtable @{
    LogName = 'Application'
    Id = 1000, 1001, 1002
    StartTime = (Get-Date).AddDays(-7)
} -MaxEvents 50 | Select-Object TimeCreated, Id, ProviderName, Message
```

## Advanced Filtering

### Filter by Provider

```powershell
# All events from a specific provider
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    ProviderName = 'Microsoft-Windows-Kernel-Power'
} -MaxEvents 20
```

### Filter by Time Range

```powershell
# Events between specific dates
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    StartTime = [datetime]'2025-12-01'
    EndTime = [datetime]'2025-12-03'
} -MaxEvents 100
```

### XPath Filtering (Advanced)

```powershell
# Custom XPath query for complex filters
Get-WinEvent -LogName System -FilterXPath "*[System[Level<=2]]" -MaxEvents 50
```

## Useful Patterns

### Group Events by Provider

```powershell
Get-WinEvent -FilterHashtable @{LogName='System';Level=1,2} -MaxEvents 200 |
    Group-Object ProviderName |
    Sort-Object Count -Descending |
    Select-Object Count, Name
```

### Export Events to CSV

```powershell
Get-WinEvent -FilterHashtable @{LogName='System';Level=1,2;StartTime=(Get-Date).AddDays(-7)} |
    Select-Object TimeCreated, Id, ProviderName, LevelDisplayName, Message |
    Export-Csv -Path "$env:TEMP\system-errors.csv" -NoTypeInformation
```

### Find Specific Keywords in Messages

```powershell
Get-WinEvent -FilterHashtable @{LogName='System';Level=1,2} -MaxEvents 500 |
    Where-Object { $_.Message -like '*memory*' -or $_.Message -like '*disk*' } |
    Select-Object TimeCreated, Id, ProviderName, Message
```

## Available Logs

### List All Event Logs

```powershell
# List all logs with event counts
Get-WinEvent -ListLog * | Where-Object { $_.RecordCount -gt 0 } |
    Sort-Object RecordCount -Descending |
    Select-Object -First 20 LogName, RecordCount, FileSize, LastWriteTime
```

### Common Diagnostic Logs

| Log Path | Purpose |
| ---------- | --------- |
| Microsoft-Windows-Kernel-Power/Operational | Power events |
| Microsoft-Windows-Storage-Storport/Operational | Storage events |
| Microsoft-Windows-NTFS/Operational | NTFS events |
| Microsoft-Windows-Diagnostics-Performance/Operational | Boot/shutdown performance |

```powershell
# Query operational logs
Get-WinEvent -LogName 'Microsoft-Windows-Diagnostics-Performance/Operational' -MaxEvents 20 |
    Select-Object TimeCreated, Id, Message
```

## Troubleshooting

### Access Denied Errors

Some logs require administrator privileges:

```powershell
# This will fail without admin
Get-WinEvent -LogName Security -MaxEvents 10
```

**Solution:** Run PowerShell as Administrator or skip Security log.

### No Events Found

```powershell
# Check if log exists and has events
Get-WinEvent -ListLog 'System' | Select-Object LogName, RecordCount, IsEnabled
```

### Performance with Large Logs

Use `-MaxEvents` to limit results and always include time filters:

```powershell
# Efficient query
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    Level = 1,2
    StartTime = (Get-Date).AddDays(-7)
} -MaxEvents 100

# Avoid: No limits (slow)
# Get-WinEvent -LogName System
```

## Quick Reference Commands

```powershell
# All critical/error events from last 24 hours
Get-WinEvent -FilterHashtable @{LogName='System','Application';Level=1,2;StartTime=(Get-Date).AddDays(-1)} -MaxEvents 100

# Unexpected shutdowns (last 30 days)
Get-WinEvent -FilterHashtable @{LogName='System';Id=41,6008;StartTime=(Get-Date).AddDays(-30)}

# Application crashes (last 7 days)
Get-WinEvent -FilterHashtable @{LogName='Application';Id=1000,1002;StartTime=(Get-Date).AddDays(-7)} -MaxEvents 50

# BSOD/bugcheck events
Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-WER-SystemErrorReporting'} -MaxEvents 20
```

---

**Last Updated:** 2025-12-03
