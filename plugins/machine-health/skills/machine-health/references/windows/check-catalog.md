# Windows check catalog

The eight seeded checks for Windows. Each section documents:

- **Script:** the `.ps1` that emits the result.
- **Category:** report grouping.
- **Needs admin:** elevation requirement.
- **Commands:** what runs.
- **Severity rubric:** per-level thresholds.
- **Notes:** gotchas and degradation behavior.

All checks emit the schema in `references/shared/output-schema.md`, use `scripts/windows/lib/Write-HealthResult.ps1`, and fall back to `UNKNOWN` with a reason rather than throw.

---

## 1. Windows Update + pending reboot

- **Script:** `scripts/windows/checks/Test-WindowsUpdate.ps1`
- **Category:** `updates`
- **Needs admin:** no for `Get-HotFix` and registry-key reads; yes for `PSWindowsUpdate` module calls (degrade to INFO if non-elevated and module present).
- **Commands:**

  ```powershell
  Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 20

  # Pending-reboot signals
  Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
  Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
  Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue

  # Optional: if PSWindowsUpdate is installed
  if (Get-Module -ListAvailable PSWindowsUpdate) { Get-WUList }
  ```

- **Severity rubric:**
  - `CRIT` — any pending security update older than 14 days (`LastInstalled` older than 14 days AND known pending).
  - `WARN` — any pending update exists (security or otherwise).
  - `INFO` — reboot pending but no pending updates older than the threshold.
  - `OK` — no pending updates, no reboot pending.

- **Notes:** Do **not** auto-install `PSWindowsUpdate`. If absent, record `notes: "PSWindowsUpdate not installed — reboot signals only"` and rely on registry pending-reboot detection for severity.

---

## 2. Disk space + SMART health

- **Script:** `scripts/windows/checks/Test-DiskHealth.ps1`
- **Category:** `storage`
- **Needs admin:** no for `Get-Volume`; yes for `Get-StorageReliabilityCounter` on some drives (degrade to `UNKNOWN` for the reliability field when blocked).
- **Commands:**

  ```powershell
  Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.FileSystem -in 'NTFS','ReFS' }
  Get-PhysicalDisk | Select-Object FriendlyName, MediaType, HealthStatus, OperationalStatus
  Get-PhysicalDisk | Get-StorageReliabilityCounter | Select-Object ReadErrorsTotal, WriteErrorsTotal, Wear, Temperature
  ```

- **Severity rubric:**
  - **Volume free space**
    - `CRIT` — any fixed NTFS/ReFS volume <5% free.
    - `WARN` — any fixed NTFS/ReFS volume <15% free.
  - **Physical health**
    - `CRIT` — `HealthStatus` is anything other than `Healthy`, or `OperationalStatus` not in `{OK, Online}`.
  - **Temperature** (when available)
    - `CRIT` — >65°C.
    - `WARN` — >55°C.
  - **Wear** (SSD indicator, when available)
    - `CRIT` — ≥85%.
    - `WARN` — ≥70%.
  - **Aggregated severity** — take the max across all volumes/disks.

- **Notes:** Temperature and wear data not available on every drive (USB-attached drives, older SATA); emit the field as `null` and record `notes: "reliability counters unavailable for <disk>"` rather than failing.

---

## 3. Event Log critical errors + BSODs

- **Script:** `scripts/windows/checks/Test-EventLogErrors.ps1`
- **Category:** `reliability`
- **Needs admin:** usually no for System log read; some event sources require admin.
- **Commands:**

  ```powershell
  Get-WinEvent -LogName System -MaxEvents 500 |
      Where-Object { $_.LevelDisplayName -in 'Error','Critical' }

  # BSODs + unexpected shutdowns
  Get-WinEvent -FilterHashtable @{ LogName='System'; ProviderName='Microsoft-Windows-WER-SystemErrorReporting' } -ErrorAction SilentlyContinue
  Get-WinEvent -FilterHashtable @{ LogName='System'; ProviderName='Microsoft-Windows-Kernel-Power'; Id=41 } -ErrorAction SilentlyContinue
  ```

- **Severity rubric:**
  - `CRIT` — any BugCheck event in last 7 days OR any `disk`-source Error/Critical event in last 7 days.
  - `WARN` — >5 repeat errors from the same `ProviderName + Id` in last 7 days.
  - `INFO` — fewer than 5 repeats; otherwise OK.

- **Notes:** Group results by `ProviderName + Id`; report top 5 by frequency with first/last occurrence timestamps in `detail`. Keep the full top-20 list in the report appendix.

---

## 4. Services + startup items

- **Script:** `scripts/windows/checks/Test-Services.ps1`
- **Category:** `services`
- **Needs admin:** no.
- **Commands:**

  ```powershell
  Get-Service | Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' }

  # Get delayed-start state via WMI (StartType is coarser)
  Get-CimInstance Win32_Service | Where-Object { $_.StartMode -eq 'Auto' }
  # DelayedAutoStart exists on Win32_Service

  Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location, User

  # System uptime for the delayed-start exception
  (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
  ```

- **Severity rubric:**
  - `WARN` — any Automatic service stopped.
  - `INFO` — Automatic-delayed-start service stopped AND system uptime <10 minutes (still starting).
  - `OK` — no stopped Automatic services.

- **Notes:** Startup items are **inventory only** — they don't drive severity here, but the list goes in the report appendix for human review. **Remediation allowed:** one `Start-Service` attempt per stopped Automatic service (see `remediation-policy.md`).

---

## 5. Defender status + threats

- **Script:** `scripts/windows/checks/Test-Defender.ps1`
- **Category:** `security`
- **Needs admin:** no for `Get-MpComputerStatus` (most fields); some fields blanked non-elevated.
- **Commands:**

  ```powershell
  Get-MpComputerStatus
  Get-MpThreatDetection
  ```

- **Severity rubric:**
  - `CRIT` — `RealTimeProtectionEnabled -eq $false` OR `IsTamperProtected -eq $false` OR any active threat detected in last 30 days OR `AntivirusSignatureAge` >7 days.
  - `WARN` — `AntivirusSignatureAge` in (3, 7] days.
  - `OK` — signatures ≤3 days old, RTP on, tamper protection on, no recent threats.

- **Notes:** If Defender is disabled because a third-party AV is active (`AMRunningMode -eq 'Passive Mode'`), note that in `detail` and downgrade severity — don't cry CRIT for a system intentionally running, say, CrowdStrike.

---

## 6. winget app updates

- **Script:** `scripts/windows/checks/Test-WingetUpgrades.ps1`
- **Category:** `updates`
- **Needs admin:** no.
- **Commands:**

  ```powershell
  winget upgrade --include-unknown --accept-source-agreements
  ```

  The skill parses the text output into a structured list: `Name`, `Id`, `CurrentVersion`, `AvailableVersion`, `Source`.

- **Severity rubric:**
  - `CRIT` — any app whose `Id` or `Name` matches an entry in `catalog/cisa-kev.json` (vendor + product substring match is acceptable as a v1; refine over time).
  - `WARN` — >10 apps behind.
  - `INFO` — 1–10 apps behind, none on KEV.
  - `OK` — no upgrades available.

- **Notes:** The full list goes in the report appendix. `catalog/cisa-kev.json` refreshed weekly by `scripts/windows/lib/Get-CisaKevCache.ps1` from `https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json` — log the outbound URL every time. If feed fetch fails, keep the cached copy and record a `notes` entry.

---

## 7. Battery + power report

- **Script:** `scripts/windows/checks/Test-Battery.ps1`
- **Category:** `power`
- **Needs admin:** no.
- **Commands:**

  ```powershell
  # Detect laptop-vs-desktop
  Get-CimInstance Win32_Battery

  # Generate a 30-day battery report (HTML). Path argument is absolute.
  powercfg /batteryreport /output "<OutputBase>\reports\battery-<date>.html" /duration 30
  ```

  The script parses the HTML for `DesignCapacity` and `FullChargeCapacity` (typically in a table near the top of the generated file) and computes `fullCapacityPct = FullChargeCapacity / DesignCapacity * 100`.

- **Severity rubric:**
  - `CRIT` — `fullCapacityPct < 50`.
  - `WARN` — `fullCapacityPct < 70`.
  - `OK` — ≥70%, or no battery present (desktop).

- **Notes:** Desktops without a battery return `OK` with `detail.has_battery: false` and a `summary: "No battery present."` — do not mark as UNKNOWN. The generated HTML report path is included in the finding's `commands` so the human can open it directly.

---

## 8. Driver inventory

- **Script:** `scripts/windows/checks/Test-Drivers.ps1`
- **Category:** `drivers`
- **Needs admin:** no.
- **Commands:**

  ```powershell
  # spellchecker:ignore-next-line
  Get-CimInstance Win32_PnPSignedDriver |
      Select-Object DeviceName, DriverVersion, DriverDate, Manufacturer, IsSigned
  ```

- **Severity rubric:**
  - `WARN` — any unsigned driver present (`IsSigned -eq $false`).
  - `INFO` — any signed driver older than 3 years.
  - `OK` — otherwise.
  - Aggregated severity = max across all drivers.

- **Notes:** Full driver inventory goes in the report appendix. The finding body should show only drivers that moved severity (unsigned drivers by name, or the oldest 5 signed drivers).
