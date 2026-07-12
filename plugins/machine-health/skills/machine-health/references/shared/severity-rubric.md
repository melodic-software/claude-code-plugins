# Severity rubric

Every check result and finding in the report carries one of five severity levels. Severity is **trend-aware** — a single reading in isolation is rarely load-bearing. Before finalizing severity, orchestrator consults `state/history.jsonl` and may adjust up or down based on delta.

## The five levels

### `OK`

System is within expected envelope for this metric. No finding rendered in report body (appears only in the collapsed "OK checks" `<details>` block).

- Disk <85% full and temperature <55°C and wear <70%.
- Defender signatures younger than 3 days, real-time protection and tamper protection on.
- No Automatic services in the stopped state.

### `INFO`

Worth knowing but no action required. Surfaces trend or context that shapes future decisions.

- Battery present on a laptop; full-charge capacity 70–100% of design.
- Driver signed and older than 3 years but not flagged by the vendor.
- Reboot pending without any old security updates.
- Automatic-delayed-start service stopped with system uptime <10 minutes (likely still starting).

### `WARN`

Action recommended this week but system still operable. A WARN today can become CRIT if ignored for a few runs — this is where trend data earns its keep.

- Disk 85–95% full, or temperature 55–65°C, or wear 70–85%.
- Defender signature age 3–7 days.
- Battery full-charge capacity 50–70% of design.
- >5 repeat errors from the same source in the System event log over 7 days.
- >10 apps behind on winget updates (none on CISA KEV).
- Automatic service stopped (non-delayed-start, or uptime ≥10 min).
- Unsigned driver present.

### `CRIT`

Action needed immediately. A pattern of ignored CRIT findings is a trust problem — rubric must stay calibrated so CRIT means CRIT.

- Disk ≥95% full, or temperature >65°C, or wear ≥85%.
- `Get-PhysicalDisk` HealthStatus is anything other than `Healthy`.
- Any BugCheck event or Kernel-Power 41 (unexpected shutdown) in the last 7 days.
- Any `disk`-source Error or Critical event in the last 7 days.
- Defender signature age >7 days, **or** real-time protection disabled, **or** tamper protection disabled, **or** any active threat in the last 30 days.
- Any winget-visible app matching the CISA KEV list.
- Pending security update older than 14 days.
- Battery full-charge capacity <50% of design.
- Authorized remediation was attempted and failed — underlying finding upgrades to CRIT with the failure message attached.

### `UNKNOWN`

Skill cannot answer the question. Never hide a gap — surface it.

- Check script timed out (90s per-check budget exceeded).
- Required cmdlet or module is missing (e.g., `Get-MpComputerStatus` blocked by policy).
- Check needs admin and run is non-elevated (do not attempt to elevate — report and move on).
- Parsing failure on vendor CLI output.
- OS is macOS or Linux and implementation is still `NOT_IMPLEMENTED`.

## The trend rule

Before finalizing a severity on a threshold boundary, orchestrator must:

1. Read last 8 entries for this `check.id` from `state/history.jsonl`.
2. Compute a delta (absolute or per-week rate where meaningful).
3. Adjust one level if trend materially changes the picture:
   - **Upgrade** by one level when a WARN metric is worsening week-over-week (e.g., disk +5pp/week).
   - **Downgrade** by one level when a metric crossed a threshold once and has reverted for two runs.
4. Write trend annotation into the finding (`"trend": { "last_run": "...", "delta": "..." }`) so the human can see the reasoning.

Never silently re-bucket. Every adjustment records its reason in `notes`.

## Why this matters

False positives erode trust in the whole routine. A weekly report that cries wolf gets skipped; a skipped report is worse than no report. When uncertain between two levels, prefer the lower and rely on trend upgrades to catch real regressions.
