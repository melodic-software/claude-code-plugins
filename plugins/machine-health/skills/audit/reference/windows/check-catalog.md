# Windows check catalog

## Contents

- [1. Windows Update + pending reboot](#1-windows-update--pending-reboot)
- [2. Disk space + SMART health](#2-disk-space--smart-health)
- [3. Event Log critical errors + BSODs](#3-event-log-critical-errors--bsods)
- [4. Services + startup items](#4-services--startup-items)
- [5. Defender status + threats](#5-defender-status--threats)
- [6. winget app updates](#6-winget-app-updates)
- [7. Battery + power report](#7-battery--power-report)
- [8. Driver inventory](#8-driver-inventory)
- [9. Reliability monitor](#9-reliability-monitor)
- [10. Scheduled tasks](#10-scheduled-tasks)
- [11. Defender exclusions](#11-defender-exclusions)
- [12. Cert expiry](#12-cert-expiry)
- [13. Container disk usage](#13-container-disk-usage)
- [14. SDK versions](#14-sdk-versions)
- [15. TPM, BitLocker](#15-tpm-bitlocker)
- [16. DNS health](#16-dns-health)
- [17. Claude Code temp root](#17-claude-code-temp-root)
- [18. Environment and PATH health](#18-environment-and-path-health)
- [19. Drive-root litter](#19-drive-root-litter)
- [21. Startup items](#21-startup-items)
- [22. App last-use](#22-app-last-use)

Per-check rubrics for Windows. Section numbers follow the order of `catalog/checks.jsonc`. Each
number is the anchor a catalog entry's `severity_rules` points at, so renumbering breaks those
pointers.

Each section documents:

- **Script:** the `.ps1` that emits the result.
- **Category:** report grouping.
- **Needs admin:** elevation requirement.
- **Commands:** what runs.
- **Severity rubric:** per-level thresholds.
- **Notes:** gotchas and degradation behavior.

All checks emit the schema in `reference/shared/output-schema.md`, and dot-source `scripts/windows/lib/Invoke-HealthCheckEnvelope.ps1`, which writes the result and falls back to `UNKNOWN` with a reason rather than throw. A check sets `$id`, `$category`, `$commands`, `$FailureSummary` and `$CheckBody` first; the script header states the contract.

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
  - `CRIT`: any pending security update older than 14 days (`LastInstalled` older than 14 days AND known pending).
  - `WARN`: any pending update exists (security or otherwise).
  - `INFO`: reboot pending but no pending updates older than the threshold.
  - `OK`: no pending updates, no reboot pending.

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
    - `CRIT`: any fixed NTFS/ReFS volume <5% free.
    - `WARN`: any fixed NTFS/ReFS volume <15% free.
  - **Physical health**
    - `CRIT`: `HealthStatus` is anything other than `Healthy`, or `OperationalStatus` not in `{OK, Online}`.
  - **Temperature** (when available)
    - `CRIT`: >65°C.
    - `WARN`: >55°C.
  - **Wear** (SSD indicator, when available)
    - `CRIT`: ≥85%.
    - `WARN`: ≥70%.
  - **Aggregated severity:** take the max across all volumes/disks.

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
  - `CRIT`: any BugCheck **or Kernel-Power 41** event in last 7 days OR any `disk`-source Error/Critical event in last 7 days.
  - `WARN`: >5 repeat errors from the same `ProviderName + Id` in last 7 days.
  - `INFO`: fewer than 5 repeats; otherwise OK.

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

  # System uptime for the delayed-start exception
  (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
  ```

- **Severity rubric:**
  - `WARN`: any Automatic service stopped.
  - `INFO`: Automatic-delayed-start service stopped AND system uptime <10 minutes (still starting).
  - `OK`: no stopped Automatic services.

- **Notes:** The startup inventory lives in [21. Startup items](#21-startup-items); this check
  reads services only. **Remediation allowed:** one `Start-Service` attempt per stopped Automatic service (see `remediation-policy.md`).

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
  - `CRIT`: `RealTimeProtectionEnabled -eq $false` OR `IsTamperProtected -eq $false` OR any active threat detected in last 30 days OR `AntivirusSignatureAge` >7 days.
  - `WARN`: `AntivirusSignatureAge` in (3, 7] days.
  - `OK`: signatures ≤3 days old, RTP on, tamper protection on, no recent threats.

- **Notes:** When a third-party AV is the active protection, Defender reports `AMRunningMode` as `Passive Mode` or `SxS Passive Mode`. Record that in `detail` and apply the passive re-bucketing: passive mode itself is `INFO`; a signature age over 3 days drops to `INFO` (the other product owns detection); real-time protection being off is not a finding at all. Tamper protection and any recorded detection keep their normal severity. Do not report CRIT for a system intentionally running, say, CrowdStrike. This is a check-local rule, independent of the ±1 trend adjustment in `reference/shared/severity-rubric.md`.

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
  - `WARN`: any upgradable app whose winget `Id`, or a shorter `.`-prefix of it, equals a KEV
    entry's `<vendorProject>.<product>` (case-insensitive), or >10 apps behind. A KEV match is a
    name match only: the feed carries no affected-version range (see the KEV feed record below)
    and the installed version is never compared, so a match against a long-patched build is
    common. The summary names the CVEs, each
    match records `match_basis: name-only`, and the appendix lists every match. The check never
    reports `CRIT`; a CRIT tier needs version evidence the check does not have. The trend rule
    never raises a KEV name-match `WARN` (`kev_match_count` > 0) either. A `WARN` from >10 apps
    behind with no KEV match can still be raised to `CRIT` when `upgrades_count` rises by 5 or more.
  - `INFO`: 1–10 apps behind, none on KEV.
  - `OK`: no upgrades available.
  - `UNKNOWN`: upgrades are pending but no usable KEV list exists (the fetch failed with no prior
    cache, the feed came back empty, or the lookup threw), so "no KEV match" cannot be vouched
    for. `ran_successfully` is false, `error` names the cause, and `detail` keeps the measured
    upgrades. A count-based `INFO` or `WARN` never stands in for a KEV check that did not run.
  - The "upgrade(s)" figure in a KEV summary counts distinct upgrade ids (`kev_upgrade_count`);
    one upgrade can match several KEV rows, counted separately as `kev_match_count`.

- **Notes:** The full list goes in the report appendix. `catalog/cisa-kev.json` refreshed weekly by `scripts/windows/lib/Get-CisaKevCache.ps1` from `https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json`. Log the outbound URL every time. `detail.kev_cache_state` records which list correlation used: `fresh`, `stale` (refresh failed, prior cache used), `unavailable` (refresh failed, no prior cache), `empty` (feed had no entries) or `unknown` (the lookup threw or returned no labeled list), with `kev_cache_age_days` beside it. If the fetch fails and a prior cache exists, keep it, keep the severity, and say so in `notes` and in the summary. With no usable list, report `UNKNOWN` as above, unless no upgrades are pending, which stays `OK` with a `notes` entry.

- **KEV feed record:**
  - Claim: a KEV entry has no field for affected versions. Its fields are `cveID`, `vendorProject`,
    `product`, `vulnerabilityName`, `dateAdded`, `shortDescription`, `requiredAction`, `dueDate`,
    `knownRansomwareCampaignUse`, `forensicTriage`, `notes` and `cwes`; the first eight are
    required.
  - Basis: the `vulnerability` definition in the feed's JSON schema,
    `https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities_schema.json`.
  - As of: 2026-09-29.
  - Recheck trigger: the schema gains a version or affected-range field, or the check starts
    comparing installed versions.

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
  - `CRIT`: `fullCapacityPct < 50`.
  - `WARN`: `fullCapacityPct < 70`.
  - `OK`: ≥70%, or no battery present (desktop).

- **Notes:** Do not mark a desktop without a battery as UNKNOWN. It returns `OK` with `detail.has_battery: false` and a `summary: "No battery present."` The generated HTML report path is included in the finding's `commands` so the human can open it directly.

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
  - `CRIT`: never from the check itself. The trend engine raises the check's WARN to CRIT when
    CodeIntegrity events appear in this run and in the last run where `drivers` ran, with an event
    newer than that run's newest (`code_integrity_newest_event_unix`). Re-reading the same event
    inside the 7-day window is not a repeat.
  - `WARN`: any CodeIntegrity 3001/3004 event in the last 7 days after the exclusion below, any
    unsigned driver in the driver store, or any device with a pnputil problem code.
  - `INFO`: any signed driver older than 3 years, or pending driver updates.
  - `OK`: otherwise.
  - Aggregated severity = max across all drivers.
  - **Defender platform exclusion:** an event is dropped before counting when every image path in
    its message sits under the active Defender platform folder
    (`...\Windows Defender\Platform\<version>\`, version read from the `WinDefend` service
    `ImagePath`). A platform rollover produces that shape routinely (see the Defender platform
    record below). An event that also names an
    image outside the folder (a Defender process loading a foreign DLL) is kept, and nothing is
    excluded when the version cannot be read. The summary reports the excluded count, and
    `code_integrity_platform_excluded_count` and `defender_platform_version` record it.
  - **Defender platform record:**
    - Claim: Defender platform binaries live in
      `%ProgramData%\Microsoft\Windows Defender\Platform\<version>`, and platform updates ship
      monthly, so a new version folder appears on that cadence.
    - Basis: Microsoft Learn,
      `https://learn.microsoft.com/en-us/defender-endpoint/command-line-arguments-microsoft-defender-antivirus`
      (folder layout) and
      `https://learn.microsoft.com/en-us/defender-endpoint/microsoft-defender-antivirus-updates`
      (monthly platform updates).
    - As of: 2026-09-29.
    - Recheck trigger: Defender changes where platform binaries load from, or either page stops
      describing the platform folder or the monthly cadence.
    - Not sourced: that the `WinDefend` service `ImagePath` names the active version folder, and
      that a rollover makes CodeIntegrity 3001/3004 events name only paths in that folder. Both
      were observed on one Windows 11 host (#4280 audit, 2026-09-19).

- **Notes:** Full driver inventory goes in the report appendix, alongside the CodeIntegrity events
  that set the severity. The finding body should show only drivers that moved severity (unsigned drivers by name, or the oldest 5 signed drivers).

---

## 9. Reliability monitor

- **Script:** `scripts/windows/checks/Test-Reliability.ps1`
- **Category:** `reliability`
- **Needs admin:** no.
- **Commands:**

  ```powershell
  Get-CimInstance Win32_ReliabilityStabilityMetrics | Sort-Object TimeGenerated -Descending | Select-Object -First 7
  Get-CimInstance Win32_ReliabilityRecords | Where-Object { $_.TimeGenerated -ge (Get-Date).AddDays(-7) }
  ```

- **Severity rubric:** the first matching row wins.
  - `CRIT`: the lowest `SystemStabilityIndex` of the last 7 daily rows is below 3.
  - `CRIT`: any record in the last 7 days whose `SourceName` matches
    `hardware|disk|memory|bugcheck|kernel-power|WER-SystemErrorReporting`.
  - `WARN`: the average `SystemStabilityIndex` of the last 7 daily rows is below 7.
  - `WARN`: any `ProductName` has 5 or more records in the last 7 days.
  - `INFO`: any record in the last 7 days, or neither the stability table nor the records
    populated.
  - `OK`: no record in the last 7 days and the stability average is 7 or higher.

- **Notes:** The hardware match is on `SourceName`, a structured provider identifier. `ProductName`
  is the crashing application's display name, so matching it would classify ordinary Windows
  component records (a `Windows Explorer` hang has `ProductName` `Windows`) as hardware failures.
  When both queries return nothing the check reports `INFO`, not `UNKNOWN`: the Reliability
  Analysis Component task may be disabled, or the host has under a day of data. The `notes` field
  then carries `schtasks /Run /TN "\Microsoft\Windows\RAC\RacTask"`. A query that throws is
  treated as empty. The 7-day record window is filtered client-side after the CIM query.

---

## 10. Scheduled tasks

- **Script:** `scripts/windows/checks/Test-ScheduledTasks.ps1`
- **Category:** `reliability`
- **Needs admin:** no.
- **Commands:**

  ```powershell
  Get-ScheduledTask | Get-ScheduledTaskInfo | Where-Object { $_.LastTaskResult -ne 0 }
  ```

- **Severity rubric:**
  - `WARN`: at least one in-scope task has a non-zero `LastTaskResult` and has run before.
  - `OK`: no such task.
  - Never `CRIT` or `INFO`.

- **Notes:** In scope are tasks in state `Ready` whose `TaskPath` does not match `\Microsoft\*`;
  that tree is OS housekeeping. A task counts as never run, and is skipped, when
  `LastTaskResult` is 267011 (`SCHED_S_TASK_HAS_NOT_RUN`) or `LastRunTime` is missing or before
  2000-01-01 (a zero FILETIME). 267014 (`SCHED_S_TASK_TERMINATED`) is deliberately not filtered:
  termination is a real event. A task whose info query throws is skipped. `detail.failed_tasks`
  lists at most 20.

---

## 11. Defender exclusions

- **Script:** `scripts/windows/checks/Test-DefenderExclusions.ps1`
- **Category:** `security`
- **Needs admin:** yes. Non-elevated, `Get-MpPreference` returns a literal `N/A: Must be
  administrator...` string in the exclusion fields, so the check gates on elevation first.
- **Commands:**

  ```powershell
  Get-MpPreference | Select-Object ExclusionPath, ExclusionExtension, ExclusionProcess
  ```

- **Severity rubric:**
  - `WARN`: at least one path exclusion matches none of the known-safe patterns.
  - `INFO`: exclusions exist and every path exclusion matches a known-safe pattern. Extension and
    process exclusions never raise the level above `INFO`.
  - `OK`: no path, extension or process exclusions.
  - `UNKNOWN`: not elevated (`needs_admin`), or `Get-MpPreference` fails, as with a third-party
    antivirus. `ran_successfully` is false and the admin-gated fields (`exclusion_path_count`,
    `exclusion_extension_count`, `exclusion_process_count`, `unexpected_path_count`) are
    withheld.
  - Never `CRIT`.

- **Known-safe path patterns:** matched with PowerShell `-like`: `*\NuGetScratch*`,
  `*\node_modules*`, `*\.dotnet*`, `*\dotnet-install*`, `*\.cache*`,
  `*\Visual Studio\Packages*`. The list is a dev-machine allowlist in the script.

- **Notes:** With no exclusions `Get-MpPreference` returns `$null` per property, and `@($null)` is a
  one-element array, so null and blank entries are dropped before counting. A pattern may match
  anywhere in the path, so any path containing one of those segments is treated as expected.
  `detail.unexpected_paths` lists at most 20.

---

## 12. Cert expiry

- **Script:** `scripts/windows/checks/Test-CertExpiry.ps1`
- **Category:** `security`
- **Needs admin:** no. The store read is `Cert:\CurrentUser\My`.
- **Commands:**

  ```powershell
  Get-ChildItem Cert:\CurrentUser\My | Select-Object Subject, Issuer, NotAfter
  ```

- **Severity rubric:** `days_left` is `floor((NotAfter - now).TotalDays)`.
  - `CRIT`: any certificate already expired (`days_left` below 0), or expiring in 7 days or fewer.
  - `WARN`: no `CRIT` certificate, and any expires in 8 to 30 days.
  - `INFO`: no `CRIT` or `WARN` certificate, and any expires in 31 to 90 days.
  - `OK`: no certificate expires within 90 days, or the store is empty.

- **Notes:** Certificates whose subject contains `DO_NOT_TRUST` or `CN=localhost` (development
  certificates) are excluded before counting. A certificate with no `NotAfter` is treated as
  never expiring. Only the current user's personal store is read; machine stores and trusted root
  stores are out of scope. `detail.expiring_soon` lists the first 20 of the `CRIT`, `WARN` and
  expired certificates. The `INFO` tier is counted but not listed.

---

## 13. Container disk usage

- **Script:** `scripts/windows/checks/Test-ContainerDiskUsage.ps1`
- **Category:** `storage`
- **Needs admin:** no.
- **Commands:**

  ```powershell
  docker system df --format '{{json .}}'
  wsl --list --verbose
  ```

- **Severity rubric:**
  - `WARN`: Docker usage above 50 GB, or WSL virtual disks above 30 GB.
  - `INFO`: either figure was measured and neither limit is exceeded.
  - `OK`: neither `docker` nor `wsl` produced a figure.
  - No `CRIT`: the data is reclaimable and has no security consequence, the same reasoning as
    section 17.

- **Notes:** Docker usage is the sum of the `Size` column across every row `docker system df`
  prints (images, containers, volumes, build cache), parsed from strings such as `12.3GB`. A row
  whose size does not parse adds nothing. WSL usage is the summed length of every file named
  `ext4.vhdx` found up to 3 levels under `%LOCALAPPDATA%\Packages`, so a virtual disk with another
  name or location is not counted. `wsl --list --verbose` only probes that WSL responds; its
  output is not parsed. Failures are appended to `notes`.

---

## 14. SDK versions

- **Script:** `scripts/windows/checks/Test-SdkVersions.ps1`
- **Category:** `updates`
- **Needs admin:** no.
- **Commands:**

  ```powershell
  dotnet --list-sdks
  node --version
  python --version
  ```

- **Severity rubric:** each detected runtime version is compared to
  `reference/shared/sdk-eol-table.json`.
  - `CRIT`: any detected version has an end-of-life date in the past.
  - `WARN`: no version is past end of life, and any reaches end of life within 90 days.
  - `INFO`: at least one runtime was detected and none is past end of life or within 90 days. The
    summary names the runtime whose end-of-life date is earliest, with unknown dates last.
  - `OK`: no runtime was detected.

- **Notes:** Versions are keyed as `major.minor` for .NET and Python (each distinct installed .NET
  `major.minor` counts once) and as `major` for Node.js. A version missing from the table has
  `state: unknown_eol` and never raises severity. If the table file is absent, every version is
  `unknown_eol`. Python is `python`, falling back to `python3`. The table is data: it needs an
  update when a vendor changes a support boundary.

---

## 15. TPM, BitLocker

- **Script:** `scripts/windows/checks/Test-TpmBitLocker.ps1`
- **Category:** `security`
- **Needs admin:** yes. Non-elevated runs return `UNKNOWN` with `needs_admin` and withhold
  `tpm_owned`, `tpm_enabled` and `bitlocker_protection_status`.
- **Commands:**

  ```powershell
  Get-Tpm
  Get-BitLockerVolume
  ```

- **Severity rubric:** the first matching row wins.
  - `WARN`: `Get-Tpm` returned nothing.
  - `WARN`: the TPM is not owned or not enabled.
  - `INFO`: the TPM is owned and enabled and no `OperatingSystem` volume is listed.
  - `WARN`: an `OperatingSystem` volume exists and none has `ProtectionStatus` `On`.
  - `OK`: the TPM is owned and enabled and an operating-system volume is protected.
  - Never `CRIT`.

- **Notes:** A `Get-BitLockerVolume` failure yields an empty volume list, which reads as the `INFO`
  row when the TPM is healthy. Only operating-system volumes drive severity; the per-volume
  list is in `detail.bitlocker_volumes` for the report. `bitlocker_protection_status` reports the
  first operating-system volume.

---

## 16. DNS health

- **Script:** `scripts/windows/checks/Test-DnsHealth.ps1`
- **Category:** `network`
- **Needs admin:** no.
- **Commands:**

  ```powershell
  Resolve-DnsName microsoft.com -Type A -DnsOnly -QuickTimeout
  Get-NetRoute -DestinationPrefix 0.0.0.0/0 | Sort-Object RouteMetric | Select-Object -First 1 | Where-Object NextHop -NE 0.0.0.0 | ForEach-Object { Test-Connection -TargetName $_.NextHop -Count 1 -TimeoutSeconds 1 }
  ```

- **Severity rubric:** the first matching row wins.
  - `CRIT`: the default gateway is known and one ICMP probe (1-second timeout) gets no reply.
  - `WARN`: `microsoft.com` or `github.com` fails to resolve an A record. The summary adds
    `(gateway unknown)` when no gateway state was obtained.
  - `INFO`: both names resolve and the gateway state is unknown.
  - `OK`: both names resolve and the gateway replies.

- **Notes:** The gateway is the lowest-metric `0.0.0.0/0` route. A `NextHop` of `0.0.0.0` (on-link
  route) or a route lookup failure leaves the gateway state unknown. DNS failures are tested
  before the unknown-gateway `INFO` so a real resolution problem is not under-reported when the
  gateway state is missing. A gateway that drops ICMP reads as unreachable, hence `CRIT`.

---

## 17. Claude Code temp root

- **Script:** `scripts/windows/checks/Test-ClaudeTempRoot.ps1`
- **Category:** `storage`
- **Needs admin:** no.
- **Commands:**

  ```powershell
  $root = if ($env:CLAUDE_CODE_TMPDIR) { Join-Path $env:CLAUDE_CODE_TMPDIR 'claude' }
          else { Join-Path $env:TEMP 'claude' }

  Get-ChildItem -LiteralPath $root -Recurse -File -Force | Measure-Object -Property Length -Sum
  Get-ChildItem -LiteralPath $root -Directory -Force |
      ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Directory -Force } |
      Measure-Object
  Get-ChildItem -Path (Join-Path $root '*\*\tasks\*.output') -File -Force |
      Sort-Object Length -Descending | Select-Object -First 5 FullName, Length, LastWriteTimeUtc
  ```

- **Root resolution:** first existing candidate wins, and the winner is recorded in
  `detail.root_source`. Every candidate ends in the literal `claude` segment. Claude Code appends
  `claude` on Windows to whatever temp base it resolves, so a bare base is never a candidate: a base
  with no `claude` child means Claude Code has not written there, and measuring the base itself would
  report an unrelated temp directory's contents as this check's finding. Bases in order:
  `CLAUDE_CODE_TMPDIR` when set, then `%TEMP%`, then `%LOCALAPPDATA%\Temp`. The resolved path is
  normalized to its long form, because `%TEMP%` commonly carries an 8.3 short name.

- **Background-task output listing:** before the walk, the check lists
  `<root>/<project-key>/<session-id>/tasks/*.output` (exactly those three directory levels, never
  recursive) and keeps the five largest in `detail.largest_task_outputs`, largest first. Each entry
  carries `path` and `session_dir` (long form), `bytes`, `gb` and `last_write_utc`.
  `detail.task_output_count` counts every match, `detail.task_output_over_count` counts every match
  at or above the per-file threshold, and `detail.largest_task_output_gb` is the top entry's size.
  Only directory listings and file metadata are read, never file contents: task output can hold
  secrets. Each directory is streamed and the 20-second cap is tested per entry on the check's own
  clock, so one `tasks` directory with millions of entries cannot hold the listing past it. Hitting
  the cap sets `detail.task_output_truncated`, and the walk keeps at least 40 of its 60 seconds.
  Whether the owning
  session is still live is not inferred, because age cannot separate a live scratchpad from an
  abandoned one (`/disk-hygiene:clean` safety model); `last_write_utc` is reported and the reader
  judges.

- **Severity rubric:**
  - `WARN`: total ≥5 GB, **or** the oldest session directory is ≥14 days old, **or** one task output
    is ≥1 GB. The summary then names the largest such file by the longest form that fits the
    240-character summary cap: full path, then the path under the root, then the file name, and says
    how many more outputs are over the threshold. The full path is always in
    `detail.largest_task_outputs`.
  - `INFO`: total ≥1 GB and no WARN arm trips.
  - `OK`: total <1 GB, **or** the root does not exist.
  - `UNKNOWN`: the walk did not complete. Its 60-second budget was exceeded, **or** any path under
    the root could not be read, **or** the walk threw, **or** the task-output listing hit its
    20-second cap. A completed walk proves the totals but not that no unlisted output reached the
    per-file threshold, so a cut-off listing takes this row too. Partial figures still ship in `detail` so the
    human sees the floor. An incomplete walk undercounts by an unbounded amount, so it cannot clear
    a threshold in either direction. An inaccessible multi-gigabyte session would otherwise read as
    `OK`. `ran_successfully = false` also keeps the run out of `checks_ran`, which is what keeps an
    undercounted `total_gb` from becoming a trend baseline that a later complete walk would exceed
    by the merely-recovered difference. A task output ≥1 GB does not lift this to `WARN`:
    `check-result.schema.json` requires `UNKNOWN` whenever `ran_successfully` is false. The task-output
    list still ships in `detail`, and the summary names the largest file and says whether the
    listing itself completed.
  - No `CRIT`. The tree is reclaimable cache with no data-loss or security consequence, and
    `reference/shared/severity-rubric.md` reserves `CRIT` for imminent-failure and security
    conditions while directing ambiguity to the lower level. `container-disk-usage`, the other
    reclaimable-storage check, caps at `WARN` for the same reason. Sustained growth still reaches
    `CRIT`: the orchestrator's trend rule upgrades a `WARN` whose `total_gb` rose ≥5 GB since the
    prior run.

- **Why the walk budget is 60s and not the orchestrator's 90s:** the orchestrator kills a check at
  90s and `check-result.schema.json` caps `duration_ms` at 90000, so an unbounded walk of a
  multi-gigabyte tree does not merely time out. It emits a schema-invalid result and loses the
  partial figures entirely. Stopping at 60s keeps them and reports `UNKNOWN` per the rubric. The
  walk streams every directory and tests the budget per entry, so one directory with millions of
  entries, or on a slow share, cannot hold it past 60s. On a cut-off walk
  `detail.project_key_count` counts only the project keys reached, a floor like the other figures.

- **Why the age arm is independent of size:** the failure this check exists for is *unpruned* growth.
  A modest tree whose oldest entry keeps aging is evidence that nothing reclaims it, which a size
  threshold alone cannot see until the volume is already at risk. The contrast case is
  `$CLAUDE_JOB_DIR/tmp`, which has a documented cleanup owner and stays small indefinitely.
  Pointer: that owner is in
  [Where state is stored](https://code.claude.com/docs/en/agent-view#where-state-is-stored). As of:
  2026-10-11. Recheck trigger: that section stops naming when the per-session scratch directory is
  removed, or is renamed.

- **Why a per-file arm, and why it runs before the walk:** a single runaway background-task output
  can hold nearly all of the tree's bytes. A total-size verdict alone never says which file to
  remove, and a tree that large is the one most likely to exhaust the walk budget. Listing three
  directory levels costs one directory read per session, not per file, so the largest outputs are
  named even when the walk cannot finish. The 1 GB threshold is this check's own decision. It holds
  whether or not the running Claude Code version caps a task's output, because a runaway file from
  an older version can still be on disk.
  - **Probed layout:** `<root>/<project-key>/<session-id>/tasks/<task-id>.output` was observed on
    live Windows sessions in
    [#6036](https://github.com/melodic-software/claude-code-plugins/issues/6036). No docs page
    names this path as of 2026-10-04.
  - **Pointer**: when deciding whether the running Claude Code version caps a background task's
    output, fetch
    [Interactive mode, "How backgrounding works"](https://code.claude.com/docs/en/interactive-mode#how-backgrounding-works)
    live. **As of**: 2026-10-18. **Recheck trigger**: that section names where task output is
    written or changes what it says about capping output size, or a probe finds `.output` files
    outside `tasks/`.

- **Remediation:** none. `machine-health` removes nothing here; `detail.remediation_route` names
  `disk-hygiene:clean`, which owns removal behind its own snapshot, tier approval, and live-handle
  checks. Its safety model treats a live session's scratchpad as an active working directory.

- **Notes:** Age is measured at the session-directory level (`<root>/<project-key>/<session-id>/`).
  A project-key directory is reused across sessions, so its own timestamp reports when the key was
  first seen, not how long the oldest unreclaimed content has survived. Unreadable paths are counted
  into `detail.unreadable_dir_count` and noted, so totals are a lower bound, never silently short.
  The check is Windows-only: `scripts/macos/` and `scripts/linux/` are `not-implemented.md` stubs, so
  there is no POSIX implementation to register and the skill reports `UNKNOWN` wholesale on those
  hosts. A POSIX port resolves its own base and per-user segment rather than copying the Windows
  candidates, and lists the same `tasks/*.output` level beneath it.
  - **Pointer**: when porting the root resolution to macOS or Linux, fetch the `CLAUDE_CODE_TMPDIR`
    row of [Environment variables](https://code.claude.com/docs/en/env-vars) live; it gives the
    per-OS default base and the segment appended on each OS. **As of**: 2026-10-04. **Recheck
    trigger**: a macOS or Linux implementation of this check is started, or that row changes.

---

## 18. Environment and PATH health

- **Script:** `scripts/windows/checks/Test-EnvironmentHealth.ps1`
- **Category:** `config`
- **Needs admin:** no. `HKCU:\Environment` is readable un-elevated; `HKLM:\...\Environment`
  usually is too. If the machine key is unreadable the check keeps User-scope findings and
  notes the gap. It does not ask for elevation.
- **Remediation:** none. `reference/windows/remediation-policy.md` bars registry cleanup of
  any kind. This check ships with no remediation entry; every fix is a human action.
- **Commands:**

  ```powershell
  Get-Item -LiteralPath 'HKCU:\Environment'
  (Get-Item -LiteralPath 'HKCU:\Environment').GetValueKind('Path')
  [Environment]::GetEnvironmentVariable('Path', 'User').Length
  Get-ItemProperty -LiteralPath 'HKCU:\Environment' -Name DISABLE_AUTOUPDATER
  Get-ChildItem Env: |
      Where-Object Name -match '(_TOKEN|_API_KEY|_SECRET|_PASSWORD)$' |
      Select-Object Name
  ```

- **Severity rubric:**
  - `CRIT`: User Path length ≥ 2047 (legacy System Properties editor ceiling; further
    appends are silently discarded).
  - `WARN` when any of these hold: User Path length ≥ 1800; User Path value kind is
    `REG_SZ` (`String`) rather than `REG_EXPAND_SZ` (`ExpandString`);
    `DISABLE_AUTOUPDATER` set to a truthy
    value (`1` / `true` / `yes` / `on`) in User or Machine scope; a persisted variable
    **name** matching `*_TOKEN`, `*_API_KEY`, `*_SECRET`, `*_PASSWORD` (or those exact
    names); an executable name resolvable from 2+ PATH directories whose winner is a
    lower-precedence scope than User while a User-scope copy also exists.
  - `INFO`: PATH entry pointing at a non-existent directory; duplicate PATH entries
    (case-insensitive, trailing-slash-normalized, across User and Machine); executable
    name present in 2+ PATH directories with a User-precedence winner; `DISABLE_AUTOUPDATER`
    present but not truthy.
  - `OK`: none of the above.
  - `UNKNOWN`: `HKCU:\Environment` could not be read.
  - Aggregated severity = max across findings.

- **What is in scope (mechanical shapes only):** persisted User and Machine environment
  values. Shadowing uses the process `$env:PATH` as the live search order and labels each
  entry `user` / `machine` / `both` / `unknown` from membership in the persisted Path
  lists. Persisted Path is read without expanding `%VAR%` tokens so `user_path_length`
  measures the stored string (legacy-editor ceiling). Directory existence and scope
  classification expand those tokens first. Otherwise stock Machine Path entries
  such as a `%SystemRoot%` system32 directory would false-positive as missing and be labeled
  `unknown`. The check does not attribute a vendor, decide whether `WindowsApps`
  belongs last, or recommend editing `TEMP`/`TMP`.

- **Safety:** credential-pattern **values are never read**. The result reports `name` and
  `scope` only. `GetValue` is not called for those names, so a summary, note, or exception
  cannot leak a secret the check never loaded. The check never writes: no `Set-Item`,
  `Set-ItemProperty`, `SetEnvironmentVariable`, or Path rewrite.

- **Notes:** a truthy persisted `DISABLE_AUTOUPDATER` turns off Claude Code's background
  updates for every session that inherits it, with no error and no prompt, which is why a set
  value is a WARN. What the variable does and does not block (manual updates, the separate
  variable that blocks every update path) is stated in
  [Disable auto-updates](https://code.claude.com/docs/en/setup#disable-auto-updates); fetch it
  live. **As of**: 2026-10-11. **Recheck trigger**: that section changes which update paths
  `DISABLE_AUTOUPDATER` stops. Duplicate and missing PATH entries are INFO because presence is a
  shape, not a verdict that the entry should be removed.

---

## 19. Drive-root litter

- **Script:** `scripts/windows/checks/Test-DriveRootLitter.ps1`
- **Category:** `storage`
- **Needs admin:** no. Listing a volume root, reading root-entry owners via `Get-Acl`, and
  probing a stray directory for emptiness all work un-elevated; when an owner or emptiness
  probe is denied anyway the field ships as `null` and severity is unaffected.
- **Remediation:** none. The check reports; it never deletes, moves, or modifies. Removal
  routes to `disk-hygiene:clean` (`detail.remediation_route`), which owns deletion behind
  its own snapshot and approval model.
- **Commands:**

  ```powershell
  Get-ChildItem -LiteralPath "$env:SystemDrive\" -Force | Select-Object Name, Mode, Length
  Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter }
  ```

- **What it detects:** entries at a fixed-volume root that nothing on the machine accounts for.
  Two representative shapes: an empty `tmp` directory left by a path translation, and a 0-byte
  `log.txt` written by an elevated process whose working directory was the root. Both files and
  directories are in scope; the listing is **non-recursive** (the root's own entries, nothing
  below them).

- **Baseline is data, not logic:** the expected-entry set lives in
  `reference/windows/drive-root-baseline.jsonc`. Admitting a newly legitimate entry is an
  edit to that file, never a script change. Names are `-like` patterns (case-insensitive,
  `*`/`?` wildcards) matched **type-aware**. A directory only matches the `directories`
  list, a file only the `files` list, so a stray file named `Recovery` cannot hide behind
  the expected directory of the same name.

- **Per-volume posture:**
  - **System drive** (`%SystemDrive%`): full baseline diff. Every root entry not matching
    `all_volumes` + `system_drive` is residue.
  - **Non-system fixed volumes** (data drives, Dev Drives): a user-managed root legitimately
    holds arbitrary content, so a baseline diff there would be all noise. Only names matching
    the `data_volume_litter` shapes (`tmp`, `temp`, `tmp.*`, `log.txt`, `*.tmp`) are
    reported; everything else is presumed intentional. A machine that deliberately keeps a
    `D:\tmp` admits it with a baseline data edit.
  - Removable and network drives are never scanned.

- **Severity rubric:**
  - `WARN`: ≥10 residue entries. Something is actively dumping at a root, action this week.
  - `INFO`: 1–9 residue entries.
  - `OK`: no residue.
  - `UNKNOWN`: the baseline file is missing or unparsable (no way to tell residue from a
    legitimate entry), **or** any root could not be listed at all (an unlistable root can
    hide any amount of litter, so partial results cannot support a threshold verdict).
    Partial residue still ships in `detail`. `ran_successfully = false` keeps such a run
    out of `checks_ran` so an undercounted `residue_count` never becomes a trend baseline.
  - No `CRIT`. Root litter is tidiness with no data-loss or security consequence, and
    `reference/shared/severity-rubric.md` reserves `CRIT` for imminent-failure and security
    conditions while directing ambiguity to the lower level. `drive-root-litter` is mapped
    to `residue_count` for history but deliberately **excluded** from the trend engine's
    generic upward upgrade for the same reason.

- **Trend behavior:** output is deterministic. Residue is sorted by volume then name, and each
  entry carries a `created` **date** (day granularity, stable across runs) rather than an
  instant, so a dropping that sits unchanged produces identical findings run over run and
  feeds the catalog's `identical_streak` demotion accounting instead of reading as news
  every week. `residue_count` is the history metric.

- **Notes:** owner (`Get-Acl`) and directory emptiness (first `EnumerateFileSystemEntries`
  hit only, since the check never recurses into a stray directory) are best-effort diagnostic
  context. An owner of `BUILTIN\Administrators` on a root entry identifies a dropping from an
  elevated process, which is the attribution this field exists to supply.
  `Get-Volume` failing (Storage module unavailable) degrades to scanning the system drive
  alone rather than `UNKNOWN`. The check is Windows-only; a POSIX port would need its own
  baseline semantics (`/` has a very different expected set) and is not scaffolded.

---

## 20. Storage top-N

- **Script:** `scripts/windows/checks/Test-StorageTopN.ps1`, walking through
  `scripts/windows/lib/Measure-FolderSize.ps1`.
- **Category:** `storage`
- **Needs admin:** no. A folder the standard token cannot list is counted in
  `detail.inaccessible_count` and the walk goes on.
- **Remediation:** none. The check sizes folders; it never opens a file for its content, moves or
  deletes anything.
- **Commands:**

  ```powershell
  $opts = [System.IO.EnumerationOptions]::new()
  $opts.RecurseSubdirectories = $false
  $opts.IgnoreInaccessible = $false
  $opts.AttributesToSkip = [System.IO.FileAttributes]::None  # placeholders are filtered per entry
  [System.IO.DirectoryInfo]::new($env:USERPROFILE).EnumerateFileSystemInfos('*', $opts)
  ```

- **Roots, in scan order:** the reclaim locations `%TEMP%` (hint `temp`), the current user's
  `%SystemDrive%\$Recycle.Bin\<SID>` (`recycle-bin`), `%ProgramData%\Package Cache`
  (`package-cache`) and `%SystemDrive%\Windows.old` (`windows-old`), then `%USERPROFILE%`. Every
  root's own level is listed before any folder is walked, so a sync root directly under a root is
  always recorded. A missing root is reported with `status` `absent`. `%TEMP%` lies under the
  profile, so it is walked twice; `detail.scanned_bytes` counts a root nested in another scanned
  root only once.
- **What it lists:** each folder directly under a root is sized by its own walk (logical `Length`
  of every file below it), and the 15 largest per root become FindingItems of kind `folder`,
  identity the full path, severity `INFO`, with `logical_bytes`, `allocated_bytes`, `file_count`,
  `complete` and `reclaim_hint`. Loose files at a root count toward that root's total only.
- **Cloud files are never hydrated.** Decision: the walk never descends a directory at or under a
  cloud sync root and never opens an enumerated file. A directory is under a sync root when
  `%OneDrive%`, `%OneDriveConsumer%` or `%OneDriveCommercial%` prefixes its path, or when it or an
  ancestor carries ReparsePoint plus one of RECALL_ON_OPEN, PINNED, UNPINNED or
  RECALL_ON_DATA_ACCESS. Each skipped sync root is one item with
  `skip_reason` `cloud-sync-root` and no size, shown as "skipped: cloud sync root"; the scalar
  `detail.skipped_sync_roots` counts them. Every other reparse directory (junction, directory
  symlink) is not descended and is counted in `detail.skipped_reparse_dirs`, as is a directory
  carrying Offline, RECALL_ON_OPEN or RECALL_ON_DATA_ACCESS. A file carrying one of those three is
  a placeholder: it is neither counted nor opened. The enumeration itself skips nothing, so such a
  directory is still seen and reported; Hidden and System entries are counted, so `AppData` is too.
  - **Pointer**: when deciding which attribute bits mark a file or directory that is not fully
    local, fetch
    [File Attribute Constants](https://learn.microsoft.com/en-us/windows/win32/fileio/file-attribute-constants)
    live. **As of**: 2026-10-21. **Recheck trigger**: that page changes the meaning or value of
    RECALL_ON_OPEN, RECALL_ON_DATA_ACCESS, PINNED or UNPINNED, or a OneDrive host shows a sync
    root that carries none of those bits and is not named by a OneDrive variable.
- **Budget:** one 60-second budget, set in `Test-StorageTopN.ps1` with the top-15 and 10,000-file
  limits and enforced in `Measure-FolderSize.ps1`, covers the scan (tested before each directory
  and each entry) and the allocated-size pass (tested before each file). It sits under the
  per-check timeout in [`SKILL.md` "Guardrails"](../../SKILL.md#guardrails), so the walk stops
  first and keeps its partial figures. Each root's walk gets an equal share of the budget left, with the allocated pass
  counted as one more claimant, and time a root leaves unused passes on; one large `%TEMP%`
  cannot starve the profile. Within a root, folders are walked in listing order, so one very large
  folder can still leave its later siblings unsized. A cut scan sets `detail.scan_complete = false`.
- **Allocated size:** a second pass calls `GetCompressedFileSizeW` on the files of each listed
  folder holding at most 10,000 files, inside the remaining budget. It skips a file that is itself
  a reparse point, since opening a file symlink reaches its target. A folder over the cap, cut by
  the budget, or with a file whose size cannot be read keeps `allocated_bytes = null`, and
  `detail.allocated_complete` is then false.
- **Severity rubric:**
  - `INFO`: any unmuted item. Every item is `INFO`: a large folder is a fact for the reader, not a
    fault.
  - `OK`: every item muted (or none listed) and the scan completed.
  - `UNKNOWN`: every item muted (or none listed) and the budget cut the scan, since a partial walk
    cannot vouch for OK; or the check threw.
  - No `WARN` or `CRIT`. Free-space pressure belongs to `disk-space` (section 2).
- **Detail scalars:** `scanned_bytes`, `top1_bytes`, `scan_complete`, `allocated_complete`,
  `inaccessible_count`, `skipped_reparse_dirs`, `skipped_sync_roots`, `items_count`,
  `muted_count`. `detail.roots[]` gives each root's `status` (`scanned`, `absent`,
  `inaccessible`, `reparse` or `cloud-sync-root`), totals and `reclaim_hint`.

---

## 21. Startup items

- **Script:** `scripts/windows/checks/Test-StartupItems.ps1`
- **Category:** `services`
- **Needs admin:** no. Without elevation `Get-ScheduledTask` lists only part of the task store, so
  `tasks_complete` is false and named in `admin_fields`; every other source reads the same either
  way.
- **Remediation:** none. The check lists; turning an entry off is the owner's action in Task
  Manager or Settings.
- **Commands:**

  ```powershell
  Get-ItemProperty HKCU:\Software\Microsoft\Windows\CurrentVersion\Run   # and RunOnce; HKLM; HKLM WOW6432Node
  Get-ChildItem ([Environment]::GetFolderPath('Startup'))           # and CommonStartup
  Get-ItemProperty HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run
  Get-ScheduledTask   # tasks with a logon trigger
  ```

- **What it lists:** one FindingItem per Run and RunOnce value (HKCU, HKLM, HKLM WOW6432Node), per
  file in the user and common Startup folders, and per scheduled task with a logon trigger. A
  Startup-folder shortcut is listed by its path; it is never opened, so its target is not resolved.
  The registry keys and folders are read directly rather than through `Win32_StartupCommand`,
  because StartupApproved is keyed by those same locations.
- **Approved state:** Explorer's StartupApproved keys record whether the owner turned an entry off.
  `approved_state` is `enabled`, `disabled` (with `disabled_at` when the value carries a time),
  `unknown` (with the value's first byte in `approved_raw_byte`), or `none` when the entry has no
  StartupApproved value or, like RunOnce, has no StartupApproved key. A logon task reads `enabled` or
  `disabled` from its task state. The decoding table lives in
  `scripts/windows/lib/Read-StartupApproved.ps1`; Microsoft does not document the encoding, and the
  fleet hosts carry first bytes the table leaves `unknown`. **As of**: 2026-10-21. **Recheck
  trigger**: a probe ties one of those bytes to an observed Task Manager state, or Microsoft
  documents the key.
- **Severity rubric:**
  - `UNKNOWN`: any unmuted item in the `unknown` approved state, or any location that read as
    `denied`, `masked`, `false-zero` or `error` (named in `unreadable_sources`).
  - `INFO`: any unmuted item otherwise.
  - `OK`: nothing starts at logon, or every item is muted.
  - Startup entries are inventory, never `WARN` or `CRIT`.
- **Notes:** each item's key is `startup:` over scope and name, or `task:` over task path and
  name, so muting one survives reordering. `enabled_count` counts what starts at logon: entries
  `enabled` or `none`.

---

## 22. App last-use

- **Script:** `scripts/windows/checks/Test-AppLastUse.ps1`
- **Category:** `config`
- **Needs admin:** no. UserAssist, the source every verdict rests on, is readable un-elevated.
  Prefetch and BAM refuse a standard token; un-elevated, `prefetch_state` and `bam_state` read
  `denied` and are named in `admin_fields`, and elevated they add launch times.
- **Remediation:** none. The check never uninstalls anything.
- **Commands:**

  ```powershell
  Get-ChildItem HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall | Get-ItemProperty   # and WOW6432Node, HKCU
  Get-AppxPackage
  Get-ItemProperty HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist\*\Count
  ```

- **Installed apps:** Uninstall entries with a display name that are neither system components nor
  updates, plus the user's packaged apps that are not framework, resource or system packages.
  `Win32_Product` is never queried: enumerating it can start Windows Installer repairs.
- **Evidence window:** `evidence_start` is the later of the OS install date and the profile's
  creation time; no launch record predates either. The window is whatever the host has, so it is
  reported as a date, never converted to a length of time.
- **Verdicts:**
  - `launched`: a launch record names the app: its AppUserModelID for a packaged app; for a Win32
    app, its DisplayIcon executable or a path under its install folder. An install folder too
    shallow to belong to one app never matches; the depth floor is in
    `scripts/windows/checks/Test-AppLastUse.ps1`.
  - `no-launch-recorded`: UserAssist read, the app could have appeared in it, and did not. Shown
    as "no launch recorded since <evidence_start>".
  - `no-evidence`: UserAssist did not read, or nothing could name the app in it: a packaged app
    with no UserAssist entry, or a Win32 app with neither an install folder nor a DisplayIcon
    executable.
  - UserAssist records shell launches only, so `no-launch-recorded` means no recorded launch, not
    proof the app was never run. The record layout is decoded in
    `scripts/windows/lib/Read-UserAssist.ps1`; Microsoft does not document it, and a host whose
    values no longer fit reads `userassist_state` `error`. **As of**: 2026-10-21. **Recheck
    trigger**: `userassist_state` reads `error` on a fleet host, or `launched_count` reads 0 where
    apps are in daily use.
- **Severity rubric:**
  - `UNKNOWN`: `userassist_state` is `denied`, `masked`, `false-zero` or `error`; or every
    unmuted app is `launched` while another source read anything but `ok` or `absent`.
  - `INFO`: any unmuted app with verdict `no-launch-recorded` or `no-evidence`.
  - `OK`: every unmuted app `launched` and every source read.
  - App use is inventory, never `WARN` or `CRIT`.
- **Notes:** items are keyed `app:` over the Uninstall subkey name or the package family name.
  `launched_count` and `userassist_state` show whether the decode works on this host.
