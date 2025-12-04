# Disk Health Reference

Comprehensive guide to disk diagnostics on Windows 11 using PowerShell.

## Overview

Disk health monitoring covers physical disk status, SMART data, filesystem integrity, and storage reliability counters.

## Physical Disk Status

### Get All Physical Disks

```powershell
Get-PhysicalDisk | Select-Object `
    FriendlyName,
    MediaType,
    BusType,
    @{N='Size_GB';E={[math]::Round($_.Size/1GB,2)}},
    HealthStatus,
    OperationalStatus
```

### Health Status Values

| Status | Meaning | Action |
| -------- | --------- | -------- |
| Healthy | Normal operation | None |
| Warning | Degraded performance or predictive failure | Investigate, backup |
| Unhealthy | Failure imminent or occurred | Replace immediately |
| Unknown | Status cannot be determined | Check connections |

### Operational Status Values

| Status | Meaning |
| -------- | --------- |
| OK | Normal operation |
| Degraded | Reduced functionality |
| Error | Not functioning |
| Lost Communication | Connection lost |
| Starting | Initializing |

## SMART Data (Reliability Counters)

SMART (Self-Monitoring, Analysis and Reporting Technology) provides early warning of disk failures.

### Get Reliability Counters

```powershell
Get-PhysicalDisk | ForEach-Object {
    $disk = $_
    $counters = $_ | Get-StorageReliabilityCounter
    [PSCustomObject]@{
        DiskName = $disk.FriendlyName
        MediaType = $disk.MediaType
        HealthStatus = $disk.HealthStatus
        Temperature = $counters.Temperature
        TemperatureMax = $counters.TemperatureMax
        ReadErrorsTotal = $counters.ReadErrorsTotal
        ReadErrorsCorrected = $counters.ReadErrorsCorrected
        ReadErrorsUncorrected = $counters.ReadErrorsUncorrected
        WriteErrorsTotal = $counters.WriteErrorsTotal
        WriteErrorsCorrected = $counters.WriteErrorsCorrected
        WriteErrorsUncorrected = $counters.WriteErrorsUncorrected
        Wear = $counters.Wear
        PowerOnHours = $counters.PowerOnHours
        StartStopCycleCount = $counters.StartStopCycleCount
    }
}
```

### Key Counters to Monitor

| Counter | Warning Signs |
| --------- | --------------- |
| Temperature | Above 50C for SSD, 55C for HDD |
| ReadErrorsUncorrected | Any value > 0 |
| WriteErrorsUncorrected | Any value > 0 |
| Wear | Above 80% for SSD (approaching end of life) |
| PowerOnHours | Context-dependent (3-5 years typical) |

### SSD Wear Level

For SSDs, the Wear counter indicates lifespan consumed:

```powershell
Get-PhysicalDisk | Where-Object { $_.MediaType -eq 'SSD' } | ForEach-Object {
    $counters = $_ | Get-StorageReliabilityCounter
    [PSCustomObject]@{
        Disk = $_.FriendlyName
        Size_GB = [math]::Round($_.Size/1GB,0)
        WearPercent = $counters.Wear
        RemainingLife = "$(100 - $counters.Wear)%"
        PowerOnHours = $counters.PowerOnHours
        PowerOnDays = [math]::Round($counters.PowerOnHours/24,0)
    }
}
```

## Volume and Partition Status

### Get All Volumes

```powershell
Get-Volume | Where-Object { $_.DriveLetter } | Select-Object `
    DriveLetter,
    FileSystemLabel,
    FileSystem,
    @{N='Size_GB';E={[math]::Round($_.Size/1GB,2)}},
    @{N='Free_GB';E={[math]::Round($_.SizeRemaining/1GB,2)}},
    @{N='Used_Pct';E={[math]::Round((1 - $_.SizeRemaining/$_.Size)*100,1)}},
    HealthStatus
```

### Check Specific Volume

```powershell
Get-Volume -DriveLetter C | Select-Object *
```

## Filesystem Integrity

### Check Dirty Bit

The dirty bit indicates the volume was not cleanly unmounted:

```powershell
# Check if volume is dirty (needs chkdsk)
fsutil dirty query C:
```

**Output:**

- "Volume - C: is NOT Dirty" = OK
- "Volume - C: is Dirty" = Needs chkdsk at next reboot

### Filesystem Statistics

```powershell
# NTFS statistics
fsutil fsinfo statistics C:

# NTFS info
fsutil fsinfo ntfsinfo C:
```

## Disk Scan (Read-Only)

### Repair-Volume -Scan

This is a read-only scan that reports errors without fixing them:

```powershell
# Scan for errors (read-only) - REQUIRES ADMIN
Repair-Volume -DriveLetter C -Scan
```

**Possible results:**

- NoErrorsFound
- ErrorsFound (suggests running SpotFix or OfflineScanAndFix)
- ScanNotSupported

## Suggested Repairs (User Runs)

The following commands modify the disk. Provide these as suggestions for the user to run manually.

### chkdsk Commands

```powershell
# Check only (read-only)
chkdsk C:

# Fix filesystem errors (requires reboot for system drive)
chkdsk C: /F

# Fix and scan for bad sectors (thorough, slow)
chkdsk C: /R

# Online scan and fix (Windows 8+)
chkdsk C: /scan
```

**Note:** For the system drive (C:), chkdsk /F or /R will schedule a scan at next reboot.

### Repair-Volume Commands

```powershell
# Quick fix using spot repair - REQUIRES ADMIN
Repair-Volume -DriveLetter C -SpotFix

# Full offline scan and fix - REQUIRES ADMIN
Repair-Volume -DriveLetter C -OfflineScanAndFix
```

## Disk Event Logs

### Recent Disk Errors

```powershell
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    ProviderName = 'disk'
    StartTime = (Get-Date).AddDays(-30)
} -MaxEvents 50 -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Id, Message
```

### NTFS Errors

```powershell
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    ProviderName = 'ntfs'
    StartTime = (Get-Date).AddDays(-30)
} -MaxEvents 50 -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Id, Message
```

### Critical Disk Event IDs

| Event ID | Provider | Meaning |
| ---------- | ---------- | --------- |
| 7 | disk | Bad block detected |
| 11 | disk | Controller error |
| 15 | disk | Device not ready |
| 51 | disk | Paging error (write failed) |
| 55 | ntfs | Filesystem corruption detected |
| 98 | ntfs | Volume repair started |
| 137 | ntfs | Volume marked dirty |

## Storage Spaces (If Used)

```powershell
# Check storage pool health
Get-StoragePool | Select-Object FriendlyName, HealthStatus, OperationalStatus

# Check virtual disks
Get-VirtualDisk | Select-Object FriendlyName, HealthStatus, OperationalStatus, ResiliencySettingName
```

## Quick Diagnostic Workflow

1. **Check physical disk health:**

   ```powershell
   Get-PhysicalDisk | Select-Object FriendlyName, HealthStatus, OperationalStatus
   ```

2. **Check SMART counters for errors:**

   ```powershell
   Get-PhysicalDisk | Get-StorageReliabilityCounter | Select-Object DeviceId, Temperature, ReadErrorsUncorrected, WriteErrorsUncorrected
   ```

3. **Check volume health:**

   ```powershell
   Get-Volume | Select-Object DriveLetter, HealthStatus, @{N='Used%';E={[math]::Round((1-$_.SizeRemaining/$_.Size)*100,1)}}
   ```

4. **Check dirty bit:**

   ```powershell
   fsutil dirty query C:
   ```

5. **Review disk events:**

   ```powershell
   Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='disk','ntfs'} -MaxEvents 20
   ```

6. **If issues found, suggest:**
   - Backup important data immediately
   - Run `chkdsk C: /R` at next reboot
   - Consider disk replacement if SMART shows errors

## Warning Signs Requiring Action

| Finding | Severity | Recommended Action |
| --------- | ---------- | ------------------- |
| HealthStatus = Warning | High | Backup immediately, plan replacement |
| HealthStatus = Unhealthy | Critical | Replace disk ASAP |
| Uncorrected errors > 0 | High | Backup, run diagnostics |
| Wear > 80% (SSD) | Medium | Plan replacement |
| Temperature > 55C | Medium | Improve cooling |
| Dirty bit set | Medium | Schedule chkdsk |
| Disk Event ID 7 | High | Bad sectors detected |

---

**Last Updated:** 2025-12-03
