# Admin Elevation Reference

Guide to administrator privileges and graceful degradation for Windows diagnostics.

## Overview

Some diagnostic operations require administrator privileges. This reference documents what requires elevation, how to detect it, and how to provide graceful degradation when running without admin rights.

## Check Current Elevation

```powershell
# Check if running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
"Running as Administrator: $isAdmin"
```

## Operations by Elevation Requirement

### No Elevation Required (Always Available)

These operations work without administrator privileges:

| Category | Operations |
| ---------- | ------------ |
| **Event Logs** | System log, Application log (Get-WinEvent) |
| **Disk Info** | Get-PhysicalDisk, Get-Volume, Get-StorageReliabilityCounter |
| **Memory** | Get-Process, Get-CimInstance Win32_OperatingSystem |
| **Devices** | Get-PnpDevice, Get-CimInstance Win32_PnPEntity |
| **Performance** | Get-Counter (most counters) |
| **System Info** | Get-Uptime, Get-ComputerInfo, Get-CimInstance |
| **Network** | Get-NetAdapter, Get-NetIPAddress, Get-NetTCPConnection |

### Elevation Required (Read-Only)

These read-only operations require administrator:

| Operation | Why Admin Needed |
| ----------- | ------------------ |
| `Get-WinEvent -LogName Security` | Security log access |
| `Repair-Volume -Scan` | Volume scan access |
| `sfc /verifyonly` | System file verification |
| `Repair-WindowsImage -CheckHealth` | DISM health check |
| Some WMI thermal queries | Hardware access |
| Some performance counters | Process details |

### Elevation Required (Write Operations)

These modify the system and require explicit user action:

| Operation | What It Does |
| ----------- | -------------- |
| `chkdsk /F` | Fixes filesystem errors |
| `chkdsk /R` | Repairs and recovers bad sectors |
| `sfc /scannow` | Repairs system files |
| `Repair-WindowsImage -RestoreHealth` | Repairs Windows image |
| `Repair-Volume -SpotFix` | Quick disk repair |
| `Repair-Volume -OfflineScanAndFix` | Full disk repair |
| `mdsched.exe` | Schedules memory test (reboot) |
| Driver installation/update | Modifies system |

## Graceful Degradation Strategy

### Pattern: Try with Fallback

```powershell
# Try operation, report if elevation needed
try {
    $result = Get-WinEvent -LogName Security -MaxEvents 10 -ErrorAction Stop
    $result | Select-Object TimeCreated, Id, Message
} catch [System.UnauthorizedAccessException] {
    Write-Warning "Security log requires administrator privileges. Skipping."
} catch {
    Write-Warning "Could not access Security log: $($_.Exception.Message)"
}
```

### Pattern: Check Before Running

```powershell
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin) {
    # Run admin-required operation
    Repair-Volume -DriveLetter C -Scan
} else {
    Write-Warning "Disk scan requires administrator privileges."
    Write-Host "To scan the disk, run this command in an elevated PowerShell:"
    Write-Host "  Repair-Volume -DriveLetter C -Scan"
}
```

### Pattern: Conditional Information

```powershell
# Build result with optional admin-only info
$result = [PSCustomObject]@{
    SystemLog = (Get-WinEvent -LogName System -MaxEvents 10 -ErrorAction SilentlyContinue).Count
    ApplicationLog = (Get-WinEvent -LogName Application -MaxEvents 10 -ErrorAction SilentlyContinue).Count
    SecurityLog = 'Requires Admin'
}

if ($isAdmin) {
    $result.SecurityLog = (Get-WinEvent -LogName Security -MaxEvents 10 -ErrorAction SilentlyContinue).Count
}

$result
```

## Common Elevation Errors

### Access Denied Messages

```text
Get-WinEvent : Attempted to perform an unauthorized operation.
Access is denied.
```

**Solution:** Run as Administrator or skip the operation.

### Repair-Volume Without Admin

```text
Repair-Volume : Access to a CIM resource was not available to the client.
```

**Solution:** Suggest user runs in elevated PowerShell.

## Reporting Elevation Requirements

When an operation requires elevation, report it clearly:

```powershell
function Write-ElevationRequired {
    param([string]$Operation, [string]$Command)

    Write-Host ""
    Write-Host "ELEVATION REQUIRED" -ForegroundColor Yellow
    Write-Host "Operation: $Operation" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To run this operation:" -ForegroundColor Cyan
    Write-Host "1. Open PowerShell as Administrator"
    Write-Host "2. Run: $Command"
    Write-Host ""
}

# Example usage
if (-not $isAdmin) {
    Write-ElevationRequired -Operation "Disk Scan" -Command "Repair-Volume -DriveLetter C -Scan"
}
```

## Skill Behavior Without Admin

When the skill runs without administrator privileges:

### Available Diagnostics

1. **Event Logs:** System and Application logs (not Security)
2. **Disk Health:** Physical disk status, SMART data, volume info
3. **Memory:** Process memory, system memory stats
4. **Hardware:** Device status, driver info
5. **Performance:** Most counters
6. **Stability:** Uptime, restart events

### Limited/Unavailable

1. **Security Log:** Cannot read
2. **Disk Scan:** Cannot run Repair-Volume -Scan
3. **SFC Verification:** Cannot run sfc /verifyonly
4. **DISM Health Check:** Cannot run Repair-WindowsImage -CheckHealth
5. **Some thermal data:** May not be available

### Reporting Strategy

For each unavailable operation:

1. Note it was skipped due to elevation
2. Provide the command for user to run manually
3. Continue with available diagnostics
4. Summarize at end what was skipped

## Suggested Message Templates

### For Skipped Read-Only Operations

```text
Note: Some diagnostic operations were skipped because they require administrator privileges:
- Security log analysis
- Disk integrity scan
- System file verification

To run a complete diagnostic, restart this operation in an elevated PowerShell session.
```

### For Suggested Repairs

```text
Based on the findings, the following repairs are recommended.
These require administrator privileges and may modify your system.

Run these commands in an elevated PowerShell (Run as Administrator):

1. System file check:
   sfc /scannow

2. DISM image repair:
   DISM /Online /Cleanup-Image /RestoreHealth

3. Disk check (will run at next reboot):
   chkdsk C: /R
```

## Quick Reference

### Check Elevation

```powershell
([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
```

### Request Elevation

To run a script elevated:

```powershell
Start-Process pwsh -Verb RunAs -ArgumentList "-File", "C:\path\to\script.ps1"
```

### Run Single Command Elevated

```powershell
Start-Process pwsh -Verb RunAs -ArgumentList "-Command", "Repair-Volume -DriveLetter C -Scan"
```

## Safety Reminder

This skill operates in **read-only mode** and will never:

- Automatically run repair commands
- Modify system settings
- Install or update drivers
- Request elevation on behalf of the user

All repair operations are provided as **suggestions** for the user to run manually in an elevated session.

---

**Last Updated:** 2025-12-03
