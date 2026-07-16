# Changelog

All notable changes to the `machine-health` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.4.0]

### Changed

- Renamed the `machine-health` skill → `check`. Update any `/machine-health:machine-health`
  invocations to `/machine-health:check`; the plugin ID (`machine-health`) is unchanged, only the
  skill's leaf name moved.

## [0.2.0]

Behavior fixes from the publish-PR review, plus cadence-aware check selection. Addresses the
findings triaged during publish as pre-existing behavior or deferred implementation.

### Added

- **Cadence-aware check selection.** A `weekly` run now defers a `cadence: monthly` check that
  ran within the last ~4 weeks, using a per-check last-run signal (`checks_ran`, a new field on
  each `state/history.jsonl` line). `on-demand` and `first-run` still run every enabled check.
  Monthly demotions in the catalog overlay are no longer advisory-only. The report's delta line
  discloses how many checks were cadence-deferred, so a total-count drop from a skip is not
  misread as a health change. `checks_ran` records a check only when it produced a *successful*
  result (a timeout, invalid output, or `ran_successfully=false` result is not counted, so a
  monthly check that failed is retried next run rather than deferred). The history tail read for
  cadence is deep enough that frequent reruns inside the interval do not push a monthly check's
  last run out of view.
- **Degraded Windows Update enumeration surfaces as INFO.** When PSWindowsUpdate is present but
  `Get-WUList` fails, the check reports INFO with `detail.update_enum_degraded = true` instead of
  a misleading OK "no pending updates" (the enumeration genuinely failed), and leaves
  `pending_update_count` null (not 0) so the failure is not persisted into the update trend.

### Fixed

- **Event-log window.** `event-log-errors` now filters the 7-day window and severity inside the
  `Get-WinEvent` query (`StartTime` + numeric `Level` 1,2) instead of reading the newest 500
  records then filtering — in-window errors older than the 500th-newest record are no longer
  dropped on busy hosts, and the numeric level is locale-independent (was localized
  `LevelDisplayName`). The no-match error (the normal path for a healthy host) is detected by
  its locale-independent error id, so a healthy non-English host reports OK, not UNKNOWN.
- **Disk trend never fired.** `disk-space` now emits a scalar worst-volume `used_pct` at the top
  level of `detail` so the history flattener persists it; disk trend deltas and escalation now work.
- **Trend object matched no schema.** `Invoke-TrendAnalysis` now emits `{ last_run, delta,
  adjusted_from }` (was a non-schema `last_severity`), matching `check-result.schema.json`
  (`additionalProperties: false`). `Assert-CheckResult` now enforces the trend sub-shape so future
  drift fails loudly. `trend.last_run` is the per-check last run, normalized to ISO 8601.
- **Battery capacity analysis never ran.** The dispatcher now passes a run-scoped `-ReportPath` to
  the battery check, so `powercfg /batteryreport` runs and wear/capacity are analyzed.
- **CISA KEV fetch escaped the egress audit.** The winget check now forwards the run `-LogPath` to
  `Get-CisaKevCache`, and the KEV fetch's egress line uses the canonical single-timestamp format
  that `Read-EgressLog` parses — the CISA fetch now appears in `urls_called`.
- **PowerShell version docs.** Reconciled the docs to the real PowerShell 7.4+ requirement
  (`#Requires -Version 7.4`, 7.x-only syntax throughout) and removed the unreachable "degrade to
  5.1" claim and dead soft-degrade branch. The skill does not run on Windows PowerShell 5.1.
- **Per-run report filenames.** Reports are written to `reports/health-<UTC-timestamp>.md` (one
  file per run, millisecond precision) so a same-day — even same-second — rerun no longer
  overwrites the earlier report.

## [0.1.0]

- Initial release: Windows workstation health audit (16 checks across storage, security, updates,
  reliability, power, network, drivers), versioned catalog with machine-local overlay, trend-aware
  severity, CISA KEV correlation, approval-gated remediations, and dated markdown reports.
  macOS/Linux scaffolded (report UNKNOWN and stop).
