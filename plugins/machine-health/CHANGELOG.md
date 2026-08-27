# Changelog

All notable changes to the `machine-health` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.11.12]

### Changed

- **Comment-residue cleanup (`/code-tidying:audit-comment-residue`).** History narration, plan/session references, and stale back-references in code comments rewritten as present-tense rationale or removed. Comment-only, no behavior change.

## [0.11.11]

### Changed

- **Comment triage pass (`/code-tidying:dissolve-comments`).** Removed zero-information
  comments (section markers restating adjacent code) in the orchestrator, several checks,
  and lib helpers, and dropped stale comment references to files that do not exist in this
  repository (`.claude/rules/powershell/testing.md`, `powershell/conventions.md`,
  `tools/shared/pester/`), keeping the substantive rationale in place. No behavior change.

## [0.11.10]

### Fixed

- **`Get-GpuDriverInfo` asks `nvidia-smi` for the fields it meant to ask for.** The query and
  format flags were written bare with a space after each comma
  (`--query-gpu=name, driver_version`), which PowerShell's argument-mode comma operator turns
  into an array that spreads into four separate argv entries. `nvidia-smi` rejected them
  (`Option driver_version is not recognized`, exit 2), so the NVIDIA branch silently produced
  nothing on real hardware while the suite's argument-agnostic mocks stayed green. Both flags
  are now single quoted tokens, and the suite gained a shadowing `nvidia-smi` stub that
  captures and asserts the exact argument vector.
- **`approved_by` records one backslash between host and user, not two.** The TODO.md migration
  built the identity as `"$env:COMPUTERNAME\\$env:USERNAME"`; PowerShell double-quoted strings
  do not treat `\` as an escape, so every migrated approval persisted a literal `HOST\\user`.
  The field is free-form audit metadata (`catalog/schemas/approvals.schema.json`) and no code
  path compares it — `Test-ApprovalGranted` reads only `approved` — so previously persisted
  values need no migration; the one-shot TODO.md path writes only when `approvals.json` is
  absent, which further bounds the reach.

## [0.11.9]

### Changed

- **The orphaned shared references are reachable from the audit README.** The maintainer README
  gained pointers to `references/shared/correlation-rules.md` (how the orchestrator applies
  correlation rules) and `references/shared/testing.md` (Pester test conventions). Purely
  additive. Progressive-disclosure audit, orphan-spoke treatment.

## [0.11.8]

### Added

- **The audit skill's directory carries a nested `AGENTS.md` with its `CLAUDE.md` shim.** Three
  contributor conventions from the human-only skill README (semantics-vs-implementation layout,
  dual-invocation script contract, stateless-checks invariant) now load for Claude on any read
  under `skills/audit/`, as pointers back to the README rather than copies. Applied from an
  instruction-placement audit (findings IP-005 through IP-007); the README remains the single
  source of truth.

## [0.11.7]

### Changed

- **Long reference files carry a `## Contents` index.** 1 reference file in this plugin gained one.

  The predicate is `audit-progressive-disclosure`'s own: a reference file over 300 lines with no
  table of contents, which both official sources agree on by that length. Scope came from the
  detector's tier classification rather than a line count, so `SKILL.md` files are excluded by
  construction: they are invocation tier, not the on-demand reference tier the rule names. Files
  with fewer than five H2s were held out, because a three-row index on a long file earns nothing and
  the doctrine offers a grep recipe instead. Purely additive, with anchors generated from each
  file's own headings and verified to resolve. Docs-hygiene sweep, L2-progressive-disclosure.

## [0.11.6]

### Changed

- **The generated options block sits under `## Configuration`.** It was under `## Tests`, a section
  about the plugin's own Pester suite. The generated table itself is unchanged; only its placement
  moved. Docs-hygiene sweep, L8-write-for-humans.

## [0.11.5]

### Changed

- **Options-reference regeneration.** `scripts/sync-plugin-options-docs.py` dropped the
  phrase `in order to` from its shared options template, per the repo's own
  write-for-humans style rule that the phrase is just `to`. The generated options
  block in `README.md` regenerated with the shorter wording; no other change.

## [0.11.4]

### Changed

- **Behavior-preserving simplification pass (repo-wide batch-simplify).** Checks:
  `Test-EnvironmentHealth.ps1` loses four unreachable INFO-upgrade arms, a duplicated
  infoBits append, and a dead initializer; one emitted notes string aligns its em dash to
  the repo's `--` idiom (a conscious output-byte deviation; a repo-wide census found no
  consumer pinning the old bytes). Lib: four comment-only corrections
  (`ConvertTo-TopMetrics`, `Get-RunDelta`, `Invoke-AllowlistedWeb`,
  `New-InvalidCatalogEntryResult` plus `Assert-CatalogEntry`), proven token-stream-identical
  outside comments. Tests: dead `-Human` branches removed from two suites' local helpers,
  provably-unreachable pad/trim branches and write-only script-scope variables dropped from
  the environment-health suite, a stale helper comment fixed, mock/fixture factories
  introduced in the KEV-cache and finding-correlation suites (mutation probes confirm the
  folded assertions still discriminate), a single-use splat inlined, and 14 repeated
  Should-Contain lines folded into a canonical-field loop. All Linux-runnable Pester suites
  green at baseline counts; Windows-only suites reported unrunnable rather than passing;
  every change independently refutation-verified.

## [0.11.3]

### Changed

- **Instruction-surface de-slop (#2891, machine-health cluster).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change. The generated options block is ignore-fenced because
  `scripts/sync-plugin-options-docs.py` still emits em dashes from its shared template.

## [0.11.2]

### Changed

- **setup:** normalized restated setup-contract prose (preamble, probe-ladder
  opening, never-writes boundary, and/or headless-reconfigure recipe as present) to the
  canonical fleet wording, keeping the operable text inline with a provenance-only citation
  (whole-repo extract-ssot batch, #2698).

## [0.11.1]

### Fixed

- **`setup` skill:** the headless reconfiguration route no longer prescribes `claude plugin
  uninstall` + reinstall. That instruction rested on an unversioned claim that `claude plugin
  install --config` is ignored once a plugin is installed, and following it dropped the plugin's
  whole stored `pluginConfigs` entry, resetting every declared option to its manifest default.
  On Claude Code 2.1.240 a plain `claude plugin install … --config` against an already-installed
  plugin prints `already installed` and still writes the value, so that is now the documented
  route — stamped with the CLI version it was verified against
  ([#3111](https://github.com/melodic-software/claude-code-plugins/issues/3111)). `apply` also
  now separates the write from its effect: the stored value changes immediately, but the running
  session's hooks keep the `CLAUDE_PLUGIN_OPTION_*` they were handed at session start, so
  verification means rerunning `check` in a FRESH session — a same-session rerun reports the old
  value, which is not a failed write. It never asserts an unobserved change.
- **Docs:** the generated options block's headless route no longer implies `--config` applies
  only at install time, and now carries the CLI version its claim was verified against
  ([#3111](https://github.com/melodic-software/claude-code-plugins/issues/3111)). The block also
  now separates the write from its effect: the value is stored immediately, but hooks are handed
  their `CLAUDE_PLUGIN_OPTION_*` at session start, so a check run in the same session still
  reports the old value and that is not a failed write. Two upstream links that pointed at empty
  backward-compatibility anchors on the settings page were repointed at the headings that hold
  the content.

## [0.11.0]

### Added

- **`environment-health` detect-only Windows check (#2866).** Eighteenth catalog check.
  Reads persisted User (`HKCU:\Environment`) and Machine environment values and emits
  mechanical shapes only: `DISABLE_AUTOUPDATER`, missing PATH directories, duplicate
  PATH entries, shadowed executables (WARN when the winner is a lower-precedence scope
  than User), User Path stored as `REG_SZ` rather than `REG_EXPAND_SZ`, User Path
  length against the 2047-character legacy-editor ceiling (WARN at 1800, CRIT at 2047),
  and credential-pattern variable **names** (`*_TOKEN`, `*_API_KEY`, `*_SECRET`,
  `*_PASSWORD`) with scope only. Credential values are never read. Missing-dir
  and scope checks expand `%VAR%` tokens; `user_path_length` still measures the
  unexpanded stored string. The check is trend-tracked as `user_path_length` but
  is not in the generic upward-worsens upgrade list (composite WARN causes).
  No remediation entry — registry writes remain unauthorized. Rubric:
  `references/windows/check-catalog.md` § 18.

## [0.10.6]

### Changed

- **Explicit `disable-model-invocation` on `audit` (#2968).** The skill now states the
  invocation mode the harness already applied for an absent key (`false`), so the choice is
  auditable and gated by `skill-quality:check` check 24. No behavior change. Rubric:
  `docs/conventions/invocation-mode/README.md`.

## [0.10.5]

### Changed

- Behavior-preserving simplifications from the repository-wide batch-simplify pass:
  duplicated helpers folded, dead code and redundant constructs removed, no functional
  change. Every group was verified by a fresh-context verifier agent against the
  plugin's own test suite.

## [0.10.4]

### Changed

- **`skills/audit/TODO.md` is now a pointer, not a policy summary.** A repo-wide derivability audit
  (#2695) spot-tested it: every load-bearing claim was reproducible from
  `references/shared/approvals.md`, `references/windows/remediation-policy.md`, and the approvals
  schema — and its denylist summary had already drifted (missing rationale and the BITS
  precondition). The file keeps the no-state banner and points at those two sources instead of
  restating them. The `scripts/linux|macos/NOT_IMPLEMENTED.md` placeholders were audited too and
  deliberately kept: they own the removal criterion (all eight seeded checks ported or explicitly
  not-applicable) that no code states.

## [0.10.3]

### Changed

- **`audit`'s Windows check catalog no longer path-cites `disk-hygiene`'s private safety model.**
  The live-scratchpad caveat is stated as an attribute of `disk-hygiene:clean`'s safety model in
  prose (encapsulation audit, Path B).
- **Test runner gains a public entry surface (#2702).** `skills/audit/scripts/run-tests.ps1` is a
  thin pass-through wrapper over the private Pester runner in `tests/`; the README invokes the
  wrapper, closing the encapsulation hit at that cite.

## [0.10.2]

### Fixed

- **Invalid catalog entries now surface as UNKNOWN findings, not silent run-log skips
  (#2575).** When `Assert-CatalogEntry` rejected an entry, the orchestrator continued
  (correct for availability) but only wrote `catalog_entry_invalid skip …` to the run
  log — so `latest.json`, severity counts, the rendered report, and the run delta showed
  nothing. A registered check with a typo (the field case: `chezmoi-drift` declaring a
  category outside the enum) was indistinguishable from a check that was never
  registered. Each rejected entry now synthesizes a schema-valid `UNKNOWN` CheckResult
  (`ran_successfully: false`, error = the assertion message) via
  `New-InvalidCatalogEntryResult` and feeds the normal reporting path. Id stays the
  entry's kebab-valid `id` when present, else a collision-checked
  `invalid-catalog-entry-<index>` fallback (against catalog / already-emitted result
  ids); category stays the declared value when legal, else `reliability`. Id-less
  overlay rows in `checks.local.jsonc` are retained through `Merge-CatalogOverlay` so
  they reach the same reporting path. The category vocabulary parity guard covers this
  helper as a fifth copy alongside the two schemas and two validators.

## [0.10.1]

### Fixed

- **NOT_IMPLEMENTED scaffold docs use a legal check category (#2576).** Linux/macOS
  `NOT_IMPLEMENTED.md` instructed `category: "platform"`, which is outside the
  check-result schema enum and would be rejected by `Assert-CheckResult`. Both
  docs now use `reliability`.

## [0.10.0]

### Added

- **`config` check category: a home for declared-configuration drift checks.** The category
  vocabulary (`drivers`, `network`, `power`, `reliability`, `security`, `services`, `storage`,
  `updates`) named machine subsystems and had no member for checks that compare declared
  configuration — dotfiles, curated package manifests, infrastructure-as-code — against live
  machine state. The first real overlay check of that shape (`chezmoi-drift`,
  melodic-software/dotfiles) shipped as `"category": "config"`, which `Assert-CatalogEntry`
  rejected; the orchestrator skipped the entry with only a run-log line, so the check silently
  never ran, and the interim fix mislabeled it `reliability` — a vocabulary for crash and
  stability telemetry, not configuration integrity. `config` is now a legal value in all four
  places the vocabulary lives: `catalog/schemas/checks.schema.json`,
  `catalog/schemas/check-result.schema.json`, `Assert-CatalogEntry`, and `Assert-CheckResult`.
  A new parity test pins the four copies together so a category added to a schema but not a
  validator (or vice versa) fails the suite instead of silently disabling checks.

## [0.9.1]

### Changed

- **Docs:** actionable `/plugin configure` guidance now uses the marketplace-qualified form
  (`<plugin>@<marketplace>`; generated option blocks use `@<marketplace>`) per
  [`docs/extensibility-contract-smoke-tests.md`](../../docs/extensibility-contract-smoke-tests.md)
  Test E (#1360). Targetless references to the flow stay unqualified.

## [0.9.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.8.1]

### Fixed

- **Finding-section template no longer renders as live markdown.** The example block in
  `report-template.md` nested a ` ```powershell ` fence inside a same-width ` ```markdown ` fence, so
  the inner closer ended the outer block early: `**Suggested action:**` rendered as real markdown and
  the trailing fence swallowed the rest of the file. The outer fence is now four backticks.

### Changed

- **Self-modification docs now target the state root and `approvals.json`.** `discovery-guide.md` and
  `remediation-philosophy.md` described the retired checkbox-in-`TODO.md` approval model and told the
  skill to write new checks and deprecations into the shipped catalog inside the plugin install
  directory. Both now route proposals to `<StateBase>/TODO.md`, approvals to
  `<StateBase>/state/approvals.json` via `/machine-health:setup`, and catalog edits to the machine-local
  overlay.
- **Setup validates against the real schema artifacts** (`catalog/schemas/checks.schema.json`,
  `approvals.schema.json`) instead of the prose reference docs, and no longer calls a config write a
  "remediation" — that term stays reserved for the audit skill's approval-gated OS actions.
- **Reference corrections and rationale.** The severity rubric lists a healthy battery as `OK` (matching
  `Test-Battery.ps1`) and its `UNKNOWN` timeout row now covers a check's own narrower budget; the
  Windows catalog records Kernel-Power 41 as `CRIT`, states the passive-AV re-bucketing levels
  explicitly, and explains why the temp-root walk stops at 60s. Guardrails, the approval-contract
  references, and the `NOT_IMPLEMENTED` stubs carry their reasons or point at the file that owns them.

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
  `CLAUDE_CODE_TMPDIR` (probing the `claude` subdirectory Claude Code creates beneath it — never the
  bare base), then `%TEMP%\claude`, then `%LOCALAPPDATA%\Temp\claude`, recording the winner in
  `detail.root_source` and normalizing an 8.3 short name to its long form. An absent root exits
  quietly at `OK` per the not-applicable rule, never `UNKNOWN`.

  Severity caps at `WARN` (≥5 GB, or an oldest session ≥14 days), matching `container-disk-usage` —
  the rubric reserves `CRIT` for imminent-failure and security conditions, and this tree is
  reclaimable cache. Sustained growth still reaches `CRIT` through the orchestrator's trend upgrade,
  which now tracks `total_gb` for this check. The age arm is independent of size because a small tree
  whose oldest entry never goes away is the unpruned-growth signal itself.

  The walk enforces its 60-second budget *during* traversal, not only between session directories.
  An explicit queue replaces `Get-ChildItem -Recurse`, which blocks until a whole subtree is
  enumerated — one session directory holding tens of thousands of files could outlast the budget on
  its own and reach the orchestrator's 90-second kill, which emits nothing at all and so loses the
  partial figures the budget exists to preserve. Reparse points are skipped rather than followed,
  matching what `-Recurse` does without `-FollowSymlink`: a junction under the temp root would
  otherwise count content living elsewhere and could cycle forever.

  An incomplete walk never reports a threshold verdict. Both ways one comes back incomplete — budget
  exhaustion and an unreadable path — now yield `UNKNOWN` with `ran_successfully = false`, partial
  detail still attached so the human sees the measured floor. Previously an unreadable path only
  added a note, so an inaccessible multi-gigabyte session could be reported as `OK` from a lower
  bound. `ran_successfully = false` is also what keeps the run out of `checks_ran`, and so keeps an
  undercounted `total_gb` from being adopted as a trend baseline.

  Windows only. `scripts/macos/` and `scripts/linux/` remain `NOT_IMPLEMENTED`, so those hosts report
  `UNKNOWN` wholesale as before; `references/windows/check-catalog.md#17-claude-code-temp-root`
  records how a POSIX port derives the root.

### Fixed

- **Trend baselines no longer come from runs in which the check did not succeed (#1637).** A failed
  or partial run still persists whatever it measured into `top_metrics` — deliberately, so the
  history line records the floor — but `Invoke-TrendAnalysis` selected the newest such value with no
  regard for `checks_ran`. Because those figures are lower bounds, the next *complete* run read the
  merely-recovered difference as growth and could upgrade its `WARN` to `CRIT` on nothing. Baseline
  selection now reuses `checks_ran`, already the repo's authority for "this check produced a usable
  result" and already read that way by `Get-CheckLastRun`. This applies to every check, not only
  `claude-temp-root`. The engine's own header also described a revert-downgrade that was never
  built; it now states that severity only ever moves up.

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
