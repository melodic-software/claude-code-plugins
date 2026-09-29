# Severity rubric

Every check result and finding in the report carries one of five severity levels. Severity is **trend-aware, upward only**. Before finalizing severity, the orchestrator consults `state/history.jsonl` and may raise a WARN to CRIT on a worsening delta or a repeat; it never lowers one (see "The trend rule").

## The five levels

### `OK`

System is within expected envelope for this metric. No finding rendered in report body (appears only in the collapsed "OK checks" `<details>` block).

- Disk <85% full and temperature <55°C and wear <70%.
- Defender signatures younger than 3 days, real-time protection and tamper protection on.
- No Automatic services in the stopped state.
- Battery present with full-charge capacity ≥70% of design.

### `INFO`

Worth knowing but no action required. Surfaces trend or context that shapes future decisions.

- Driver signed and older than 3 years but not flagged by the vendor.
- Reboot pending without any old security updates.
- Automatic-delayed-start service stopped with system uptime <10 minutes (likely still starting).

### `WARN`

Action recommended this week but system still operable. A WARN today can become CRIT if ignored for a few runs. This is where trend data earns its keep.

- Disk 85–95% full, or temperature 55–65°C, or wear 70–85%.
- Defender signature age 3–7 days.
- Battery full-charge capacity 50–70% of design.
- >5 repeat errors from the same source in the System event log over 7 days.
- >10 apps behind on winget updates.
- A winget-visible app whose id name-matches the CISA KEV list. The installed version is never compared, so a match is evidence to check, not proof of exposure.
- Automatic service stopped (non-delayed-start, or uptime ≥10 min).
- Unsigned driver present, or a CodeIntegrity 3001/3004 event in the last 7 days outside the active Defender platform folder.

### `CRIT`

Action needed immediately. A pattern of ignored CRIT findings is a trust problem. The rubric must stay calibrated so CRIT means CRIT.

- Disk ≥95% full, or temperature >65°C, or wear ≥85%.
- `Get-PhysicalDisk` HealthStatus is anything other than `Healthy`.
- Any BugCheck event or Kernel-Power 41 (unexpected shutdown) in the last 7 days.
- Any `disk`-source Error or Critical event in the last 7 days.
- Defender signature age >7 days, **or** real-time protection disabled, **or** tamper protection disabled, **or** any active threat in the last 30 days. The signature-age and real-time-protection arms do not apply when Defender runs in passive mode behind a third-party AV. See `reference/windows/check-catalog.md` § 5.
- CodeIntegrity events in consecutive runs of `drivers`, with a newer event since the prior run (the trend rule below).
- Pending security update older than 14 days.
- Battery full-charge capacity <50% of design.
- Authorized remediation was attempted and failed. The underlying finding upgrades to CRIT with the failure message attached.

### `UNKNOWN`

Skill cannot answer the question. Never hide a gap. Surface it.

- Check script exceeded a time budget: the orchestrator's 90s per-check kill, or a narrower budget a check enforces on itself (e.g. `claude-temp-root` stops walking at 60s and reports partial figures).
- Required cmdlet or module is missing (e.g., `Get-MpComputerStatus` blocked by policy).
- Check needs admin and run is non-elevated (do not attempt to elevate, just report and move on).
- Parsing failure on vendor CLI output.
- OS is macOS or Linux and implementation is still `NOT_IMPLEMENTED`.

## The trend rule

Before finalizing a severity on a threshold boundary, orchestrator must:

1. Read last 8 entries for this `check.id` from `state/history.jsonl`.
2. Compute a delta (absolute or per-week rate where meaningful).
3. Adjust upward only, one level, from WARN to CRIT, when trend materially changes the picture:
   - The check's trend metric worsened by 5 or more against the last run where the check ran (e.g., disk +5pp).
   - `drivers` saw CodeIntegrity events in this run and in the last run where it ran, with a newer event since
     (`check-catalog.md` §8). One run's events stay WARN.
   - Not a `winget-upgrades` WARN that name-matches the CISA KEV list: that match is name-only evidence, so a count
     trend never raises it. A `winget-upgrades` WARN from >10 apps behind with no KEV match is raised like any other.
4. Write trend annotation into the finding (`"trend": { "last_run": "...", "delta": "...", "adjusted_from": "..." }`) so the human can see the reasoning.

Severity never moves down. No rule demotes a reading that crossed a threshold and later reverted, so a check's own
thresholds carry the false-positive burden. A first run (or the first run of a check) has no history, so its
severities are single, unmoderated readings.

After the trend rule and correlation, a custom check registered through the catalog overlay is capped at WARN until
history shows it reporting OK or INFO in 3 runs (`catalog-overlay.md`, "Custom checks"). Shipped checks are never capped.

Never silently re-bucket. Every adjustment records its reason in `notes`.

## Why this matters

False positives erode trust in the whole routine. A weekly report that cries wolf gets skipped; a skipped report is worse than no report. When uncertain between two levels, prefer the lower and rely on trend upgrades to catch real regressions.
