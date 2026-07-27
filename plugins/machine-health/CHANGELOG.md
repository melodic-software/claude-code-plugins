# Changelog

All notable changes to the `machine-health` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.8.0]

### Added

- **`claude-temp-root` check: detection for Claude Code's unpruned temp root (#1637).** The tree
  under `%TEMP%\claude` accumulates a per-session scratchpad and task-output directory and nothing
  reclaims them. Measured on the reporting machine: **7.88 GB across 377 session directories in 45
  project keys, 42,042 files, oldest 13 days** — with 6.47 GB of that in the 66 sessions already 8+
  days old, so the growth is retention, not working set. The contrast surface is
  `$CLAUDE_JOB_DIR/tmp`, which has a documented cleanup owner and stays negligible. Detection had no
  owner: `disk-hygiene:clean` owns removal but is `disable-model-invocation: true`, so it never
  notices growth on its own.

  The check reports total size, file count, session-directory count, project-key count, largest
  session, and oldest-session age, and routes removal to `disk-hygiene:clean` in
  `detail.remediation_route` — `machine-health` deletes nothing. Root resolution honors
  `CLAUDE_CODE_TMPDIR` (probing both a `claude` subdirectory beneath it and the variable as the root
  itself), then `%TEMP%\claude`, then `%LOCALAPPDATA%\Temp\claude`, recording the winner in
  `detail.root_source` and normalizing an 8.3 short name to its long form. An absent root exits
  quietly at `OK` per the not-applicable rule, never `UNKNOWN`.

  Severity caps at `WARN` (≥5 GB, or an oldest session ≥14 days), matching `container-disk-usage` —
  the rubric reserves `CRIT` for imminent-failure and security conditions, and this tree is
  reclaimable cache. Sustained growth still reaches `CRIT` through the orchestrator's trend upgrade,
  which now tracks `total_gb` for this check. The age arm is independent of size because a small tree
  whose oldest entry never goes away is the unpruned-growth signal itself.

  Windows only. `scripts/macos/` and `scripts/linux/` remain `NOT_IMPLEMENTED`, so those hosts report
  `UNKNOWN` wholesale as before; `references/windows/check-catalog.md#17-claude-code-temp-root`
  records how a POSIX port derives the root.

## [0.7.1]

### Fixed

- **Headless reconfigure recipe now preserves install scope (#1406).** The `claude plugin
  uninstall` → `claude plugin install ... --config` recipe in `skills/setup/SKILL.md` defaulted
  both halves to `-s user`. When this plugin is installed at `project` or `local` scope, that
  silently uninstalled a separate user-scope record while the effective project/local install kept
  loading, and the reinstall landed at a scope that does not load. Both commands now carry
  `-s <scope>`, sourced from what `claude plugin list` reports for this plugin — the same fix
  already applied to `session-flow` and `rate-limit-guard` in #1393.

## [0.7.0]

### Fixed

- **The hardcoded `$HOME/.claude/plugins/data/machine-health` fallback is removed from both the
  `setup` and `audit` skills.** The fallback was not a safe default — it was a second, wrong state
  root. The directory under `~/.claude/plugins/data/` is named for the plugin's *install identity*
  (`machine-health-<marketplace>`, or `machine-health-inline` for a `--plugin-dir` session), so the
  guessed path never names the directory the plugin actually uses. Observed on a real machine: the
  catalog overlay and a registered custom check sat under `machine-health/` while the audit's
  `state/` and `logs/` sat under `machine-health-melodic-software/` — a split in which the
  operator's disabled checks silently stopped taking effect and each half looked complete to
  whatever wrote it. The defect was confined to the two skills' prose — the orchestrator script's
  own ladder (`-StateBase`, else `CLAUDE_PLUGIN_DATA`, else `-OutputBase`) never named the bad path
  and is unchanged. The two skills now diverge according to what each actually does: `setup` reads
  and writes the overlay directly and has no further rung, so it FAILs at `check` step 1 and writes
  nothing when the token does not expand — with the root unresolved, "absent overlay" and
  "unreadable overlay" are the same observation and "shipped defaults in effect" would assert more
  than the evidence supports; `audit` passes `-StateBase <report-root>` explicitly instead and
  reports that the plugin-specific root could not be resolved. Falling through to the orchestrator's
  environment ladder is what `audit` must not do: a skill-invoked tool subprocess inherits whichever
  plugin's `CLAUDE_PLUGIN_DATA` its parent already carried, so the ladder can silently land this
  plugin's `state/`, `logs/`, and catalog overlay inside an unrelated plugin's directory. Colocating
  state with the reports is wrong-but-visible; the inherited variable is wrong-and-silent.
- **The `audit` skill no longer cites a repository-level document.** Its warning about the inherited
  `CLAUDE_PLUGIN_DATA` pointed at `docs/extensibility-contract-smoke-tests.md`, a path absent from
  the isolated plugin cache this skill runs from — where the link resolves against the *consuming*
  repository and is normally missing, or worse names an unrelated consumer file. The mechanism is
  now stated where the reader needs it, with no pointer that cannot be followed.
- **The README no longer states that `${CLAUDE_PLUGIN_DATA}` resolves to
  `~/.claude/plugins/data/machine-health`.** It does not, for any installed or inline plugin. The
  migration step that told operators to move `state/` there was directing them into the wrong
  directory; it now describes how the directory is named and routes to `/machine-health:setup check`
  to print the resolved path.

### Added

- **`check` reports a split state root.** Because an earlier version wrote the hardcoded path, the
  check probes that legacy path and any `machine-health-*` sibling of the resolved root, names what
  each holds, and states that only the resolved root is read. Consolidating is left to the operator
  — the stray directory holds their data, and this skill neither relocates nor removes files.

## [0.6.1]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.6.0]

### Changed

- **`/machine-health:setup` adopts the uniform setup contract** (fleet conformance wave). The skill
  now splits into a read-only `check` action (default) that reports the effective catalog overlay,
  remediation approvals, and pending proposals against the shipped catalog — treating an absent
  overlay or approvals file as INFO (the shipped zero-config default) and FAILing only a
  configured-but-broken overlay/approvals (malformed, targeting an unknown check or remediation, or a
  custom-check `script` that is missing) — and an `apply` action that writes the machine-local
  overlay and approvals. The previous interactive interview (walk proposals, tune the catalog,
  register custom checks, seed approvals) becomes `apply`'s interview path, run when no write
  arguments are supplied in an interactive session; `apply disable=<id>` / `deprecate=<id>` /
  `demote=<id>` / `approve=<id>` now apply those changes non-interactively. Custom-check registration
  stays interactive (it authors a script). Remediation approvals remain an explicit user decision.

## [0.5.0]

### Changed

- **Breaking:** renamed the `check` skill → `audit`. Update any `/machine-health:check`
  invocations to `/machine-health:audit`; the plugin ID (`machine-health`) is unchanged, only the
  skill's leaf name moved. Rationale: the skill emits a findings report rather than a pass/fail
  gate — the marketplace naming grammar reserves `check` for deterministic gates and `audit` for
  read-only reports.

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
