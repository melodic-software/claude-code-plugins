# Windows check catalog

Per-check rubrics for Windows. Section numbers follow the order of `catalog/checks.jsonc` and are
load-bearing — each is the anchor a catalog entry's `severity_rules` points at, so renumbering breaks
those pointers. Sections 9–16 have not been written yet; their catalog entries point at anchors that
do not resolve.

Each section documents:

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
  - `CRIT` — any BugCheck **or Kernel-Power 41** event in last 7 days OR any `disk`-source Error/Critical event in last 7 days.
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

- **Notes:** When a third-party AV is the active protection, Defender reports `AMRunningMode` as `Passive Mode` or `SxS Passive Mode`. Record that in `detail` and apply the passive re-bucketing: passive mode itself is `INFO`; a signature age over 3 days drops to `INFO` (the other product owns detection); real-time protection being off is not a finding at all. Tamper protection and any recorded detection keep their normal severity — but don't cry CRIT for a system intentionally running, say, CrowdStrike. This is a check-local rule, independent of the ±1 trend adjustment in `references/shared/severity-rubric.md`.

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
  ```

- **Root resolution:** first existing candidate wins, and the winner is recorded in
  `detail.root_source`. Every candidate ends in the literal `claude` segment — Claude Code appends
  `claude` on Windows to whatever temp base it resolves, so a bare base is never a candidate: a base
  with no `claude` child means Claude Code has not written there, and measuring the base itself would
  report an unrelated temp directory's contents as this check's finding. Bases in order:
  `CLAUDE_CODE_TMPDIR` when set, then `%TEMP%`, then `%LOCALAPPDATA%\Temp`. The resolved path is
  normalized to its long form — `%TEMP%` commonly carries an 8.3 short name.

- **Severity rubric:**
  - `WARN` — total ≥5 GB, **or** the oldest session directory is ≥14 days old.
  - `INFO` — total ≥1 GB and neither WARN arm trips.
  - `OK` — total <1 GB, **or** the root does not exist.
  - `UNKNOWN` — the walk did not complete: the 60-second budget was exceeded, **or** any path under
    the root could not be read, **or** the walk threw. Partial figures still ship in `detail` so the
    human sees the floor. An incomplete walk undercounts by an unbounded amount, so it cannot clear
    a threshold in either direction — an inaccessible multi-gigabyte session would otherwise read as
    `OK`. `ran_successfully = false` also keeps the run out of `checks_ran`, which is what keeps an
    undercounted `total_gb` from becoming a trend baseline that a later complete walk would exceed
    by the merely-recovered difference.
  - No `CRIT`. The tree is reclaimable cache with no data-loss or security consequence, and
    `references/shared/severity-rubric.md` reserves `CRIT` for imminent-failure and security
    conditions while directing ambiguity to the lower level. `container-disk-usage` — the other
    reclaimable-storage check — caps at `WARN` for the same reason. Sustained growth still reaches
    `CRIT`: the orchestrator's trend rule upgrades a `WARN` whose `total_gb` rose ≥5 GB since the
    prior run.

- **Why the walk budget is 60s and not the orchestrator's 90s:** the orchestrator kills a check at
  90s and `check-result.schema.json` caps `duration_ms` at 90000, so an unbounded walk of a
  multi-gigabyte tree does not merely time out — it emits a schema-invalid result and loses the
  partial figures entirely. Stopping at 60s keeps them and reports `UNKNOWN` per the rubric.

- **Why the age arm is independent of size:** the failure this check exists for is *unpruned* growth.
  A modest tree whose oldest entry keeps aging is evidence that nothing reclaims it, which a size
  threshold alone cannot see until the volume is already at risk. The contrast case is
  `$CLAUDE_JOB_DIR/tmp`, which has a documented cleanup owner and stays small indefinitely.

- **Remediation:** none. `machine-health` removes nothing here; `detail.remediation_route` names
  `disk-hygiene:clean`, which owns removal behind its own snapshot, tier approval, and live-handle
  checks. Its safety model treats a live session's scratchpad as an active working directory.

- **Notes:** Age is measured at the session-directory level (`<root>/<project-key>/<session-id>/`).
  A project-key directory is reused across sessions, so its own timestamp reports when the key was
  first seen, not how long the oldest unreclaimed content has survived. Unreadable paths are counted
  into `detail.unreadable_dir_count` and noted — totals are a lower bound, never silently short.
  The check is Windows-only: `scripts/macos/` and `scripts/linux/` are `NOT_IMPLEMENTED` stubs, so
  there is no POSIX implementation to register and the skill reports `UNKNOWN` wholesale on those
  hosts. A POSIX port derives the root the same way, appending the Unix segment (`claude-{uid}`) to
  `$CLAUDE_CODE_TMPDIR` then `$TMPDIR` then `/tmp`.

---

## 18. Environment and PATH health

- **Script:** `scripts/windows/checks/Test-EnvironmentHealth.ps1`
- **Category:** `config`
- **Needs admin:** no. `HKCU:\Environment` is readable un-elevated; `HKLM:\...\Environment`
  usually is too. If the machine key is unreadable the check keeps User-scope findings and
  notes the gap — it does not ask for elevation.
- **Remediation:** none. `references/windows/remediation-policy.md` bars registry cleanup of
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
  - `CRIT` — User Path length ≥ 2047 (legacy System Properties editor ceiling; further
    appends are silently discarded).
  - `WARN` — any of: User Path length ≥ 1800; User Path value kind is `REG_SZ` (`String`)
    rather than `REG_EXPAND_SZ` (`ExpandString`); `DISABLE_AUTOUPDATER` set to a truthy
    value (`1` / `true` / `yes` / `on`) in User or Machine scope; a persisted variable
    **name** matching `*_TOKEN`, `*_API_KEY`, `*_SECRET`, `*_PASSWORD` (or those exact
    names); an executable name resolvable from 2+ PATH directories whose winner is a
    lower-precedence scope than User while a User-scope copy also exists.
  - `INFO` — PATH entry pointing at a non-existent directory; duplicate PATH entries
    (case-insensitive, trailing-slash-normalized, across User and Machine); executable
    name present in 2+ PATH directories with a User-precedence winner; `DISABLE_AUTOUPDATER`
    present but not truthy.
  - `OK` — none of the above.
  - `UNKNOWN` — `HKCU:\Environment` could not be read.
  - Aggregated severity = max across findings.

- **What is in scope (mechanical shapes only):** persisted User and Machine environment
  values. Shadowing uses the process `$env:PATH` as the live search order and labels each
  entry `user` / `machine` / `both` / `unknown` from membership in the persisted Path
  lists. The check does not attribute a vendor, decide whether `WindowsApps` belongs last,
  or recommend editing `TEMP`/`TMP`.

- **Safety:** credential-pattern **values are never read**. The result reports `name` and
  `scope` only. `GetValue` is not called for those names, so a summary, note, or exception
  cannot leak a secret the check never loaded. The check never writes: no `Set-Item`,
  `Set-ItemProperty`, `SetEnvironmentVariable`, or Path rewrite.

- **Notes:** `DISABLE_AUTOUPDATER` is the Claude Code / Electron auto-update kill switch.
  A User-scope `=1` silently freezes the installed binary — the defect that motivated
  this check. Duplicate and missing PATH entries are INFO because presence is a shape,
  not a verdict that the entry should be removed.
