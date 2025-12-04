# Hardware Errors Reference

Comprehensive guide to detecting and analyzing hardware errors on Windows 11.

## Overview

Hardware error detection covers device failures, driver issues, WHEA (Windows Hardware Error Architecture) events, and peripheral problems.

## Device Status Check

### All Devices with Problems

```powershell
Get-PnpDevice -PresentOnly | Where-Object { $_.Status -ne 'OK' } |
    Select-Object Class, FriendlyName, InstanceId, Status, Problem |
    Sort-Object Class
```

### Status Values

| Status | Meaning |
| -------- | --------- |
| OK | Device working properly |
| Error | Device has a problem |
| Degraded | Device working but with issues |
| Unknown | Status cannot be determined |

### Specific Device Classes

```powershell
# Display adapters
Get-PnpDevice -Class Display | Select-Object FriendlyName, Status, Problem

# Network adapters
Get-PnpDevice -Class Net | Select-Object FriendlyName, Status, Problem

# Disk drives
Get-PnpDevice -Class DiskDrive | Select-Object FriendlyName, Status, Problem

# USB controllers
Get-PnpDevice -Class USB | Select-Object FriendlyName, Status, Problem
```

### Device Error Codes

```powershell
# Devices with error codes
Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 } |
    Select-Object Name, DeviceID, ConfigManagerErrorCode, Status
```

**Common Error Codes:**

| Code | Meaning |
| ------ | --------- |
| 1 | Device not configured correctly |
| 3 | Driver may be corrupted |
| 10 | Device cannot start |
| 12 | Resource conflict |
| 14 | Restart required |
| 22 | Device disabled |
| 24 | Device not present |
| 28 | Drivers not installed |
| 31 | Device not working properly |
| 43 | Device stopped (reported a problem) |

## WHEA (Windows Hardware Error Architecture)

WHEA detects and reports hardware errors from CPU, memory, PCIe, and other components.

### Query WHEA Events

```powershell
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    ProviderName = 'Microsoft-Windows-WHEA-Logger'
    StartTime = (Get-Date).AddDays(-30)
} -MaxEvents 50 -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Id, LevelDisplayName, Message
```

### WHEA Event Types

| Event ID | Meaning |
| ---------- | --------- |
| 17 | Fatal hardware error |
| 18 | Corrected hardware error |
| 19 | Informational (error source initialized) |
| 20 | Error threshold exceeded |
| 47 | Corrected Machine Check |

### WHEA Error Categories

```powershell
# Group WHEA errors by type
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    ProviderName = 'Microsoft-Windows-WHEA-Logger'
    StartTime = (Get-Date).AddDays(-30)
} -ErrorAction SilentlyContinue |
    Group-Object Id |
    Select-Object Count, @{N='EventId';E={$_.Name}},
        @{N='Sample';E={($_.Group | Select-Object -First 1).Message.Substring(0, [Math]::Min(100, ($_.Group | Select-Object -First 1).Message.Length))}}
```

## Driver Issues

### Recently Installed/Updated Drivers

```powershell
# Recent driver installations
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    ProviderName = 'Microsoft-Windows-DriverFrameworks-UserMode'
    StartTime = (Get-Date).AddDays(-7)
} -MaxEvents 50 -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Message
```

### Driver Signing Issues

```powershell
# Check for unsigned drivers (requires admin)
Get-WmiObject Win32_PnPSignedDriver | Where-Object { $_.IsSigned -eq $false } |
    Select-Object DeviceName, DriverVersion, DriverProviderName, IsSigned
```

### Driver Crash Events

```powershell
# Driver-related crash events
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    Level = 1,2  # Critical, Error
    StartTime = (Get-Date).AddDays(-7)
} -MaxEvents 100 |
    Where-Object { $_.Message -like '*driver*' } |
    Select-Object TimeCreated, Id, ProviderName, Message
```

## CPU Errors

### CPU-Related Events

```powershell
# Processor errors
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    ProviderName = 'Microsoft-Windows-Kernel-Processor-Power'
    StartTime = (Get-Date).AddDays(-30)
} -MaxEvents 20 -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Id, Message
```

### CPU Throttling Detection

```powershell
# Current CPU speed vs max
Get-CimInstance Win32_Processor | Select-Object `
    Name,
    NumberOfCores,
    NumberOfLogicalProcessors,
    CurrentClockSpeed,
    MaxClockSpeed,
    @{N='Throttled';E={if($_.CurrentClockSpeed -lt $_.MaxClockSpeed*0.9){'Possibly'}else{'No'}}}
```

### Thermal Events

```powershell
# Attempt to get thermal zone temperature (not always available)
Get-CimInstance -Namespace root\wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue |
    Select-Object InstanceName,
        @{N='TempCelsius';E={[math]::Round(($_.CurrentTemperature - 2732) / 10, 1)}}
```

**Note:** Temperature data may not be available on all systems. Use manufacturer tools or HWiNFO for reliable temperature monitoring.

## Storage Controller Errors

### AHCI/NVMe Controller Events

```powershell
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    ProviderName = 'stornvme', 'storahci', 'disk'
    Level = 1,2,3
    StartTime = (Get-Date).AddDays(-30)
} -MaxEvents 50 -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, ProviderName, Id, Message
```

## USB Issues

### USB Device Problems

```powershell
# USB devices with errors
Get-PnpDevice -Class USB | Where-Object { $_.Status -ne 'OK' } |
    Select-Object FriendlyName, Status, Problem, InstanceId

# USB hub problems
Get-PnpDevice -Class 'USB Hub' -ErrorAction SilentlyContinue |
    Select-Object FriendlyName, Status
```

### USB Power Events

```powershell
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    ProviderName = 'Microsoft-Windows-USB-USBHUB3-DriverEtwProvider'
    StartTime = (Get-Date).AddDays(-7)
} -MaxEvents 20 -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Message
```

## GPU/Display Issues

### Display Adapter Status

```powershell
Get-PnpDevice -Class Display | Select-Object FriendlyName, Status, Problem, InstanceId

# GPU driver info
Get-CimInstance Win32_VideoController | Select-Object `
    Name,
    DriverVersion,
    DriverDate,
    Status,
    @{N='VRAM_GB';E={[math]::Round($_.AdapterRAM/1GB,2)}}
```

### Display/GPU Events

```powershell
# Display driver crashes (TDR)
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    ProviderName = 'Display'
    Level = 1,2,3
    StartTime = (Get-Date).AddDays(-7)
} -MaxEvents 20 -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Id, Message
```

**TDR (Timeout Detection and Recovery):** Windows resets the GPU driver if it stops responding. Frequent TDRs indicate GPU driver or hardware issues.

## Power Supply Issues

Power supply problems don't log directly but cause symptoms:

### Signs of PSU Issues

```powershell
# Multiple unexpected shutdowns could indicate PSU
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    Id = 41  # Kernel-Power unexpected shutdown
    StartTime = (Get-Date).AddDays(-30)
} -ErrorAction SilentlyContinue | Measure-Object | Select-Object Count

# Disk errors could indicate power issues
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    ProviderName = 'disk'
    Level = 1,2
    StartTime = (Get-Date).AddDays(-30)
} -ErrorAction SilentlyContinue | Measure-Object | Select-Object Count
```

**PSU Warning Signs:**

- Random shutdowns under load
- System won't boot sometimes
- Multiple component failures
- USB devices disconnecting

## Quick Diagnostic Workflow

1. **Check all device errors:**

   ```powershell
   Get-PnpDevice -PresentOnly | Where-Object { $_.Status -ne 'OK' }
   ```

2. **Check WHEA errors:**

   ```powershell
   Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-WHEA-Logger'} -MaxEvents 20 -ErrorAction SilentlyContinue
   ```

3. **Check for driver crashes:**

   ```powershell
   Get-WinEvent -FilterHashtable @{LogName='System';Level=1,2} -MaxEvents 50 | Where-Object { $_.Message -like '*driver*' }
   ```

4. **Check specific hardware categories:**
   - GPU: `Get-PnpDevice -Class Display`
   - Storage: `Get-PnpDevice -Class DiskDrive`
   - Network: `Get-PnpDevice -Class Net`
   - USB: `Get-PnpDevice -Class USB`

5. **If errors found:**
   - Update drivers
   - Check connections
   - Test with different hardware if available
   - Consider RMA/replacement for persistent issues

## Warning Signs Requiring Action

| Finding | Severity | Recommended Action |
| --------- | ---------- | ------------------- |
| WHEA errors (any) | High | Hardware investigation needed |
| Device Status = Error | High | Update driver, check hardware |
| Error Code 43 | High | Driver issue, reinstall/update |
| Multiple TDR events | Medium-High | Update GPU driver, check cooling |
| USB disconnections | Medium | Check cables, ports, power |
| Driver crash events | Medium | Update affected drivers |
| CPU throttling | Medium | Check cooling, thermal paste |

## Suggested Actions (User Runs)

```powershell
# Update all drivers via Windows Update
# Settings > Windows Update > Check for updates > Advanced options > Optional updates

# Device Manager (GUI)
devmgmt.msc

# Check System Information
msinfo32

# DirectX Diagnostic (GPU issues)
dxdiag
```

---

**Last Updated:** 2025-12-03
