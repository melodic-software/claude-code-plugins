# Changelog

All notable changes to the `context-budget` plugin.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.1]

### Changed

- Tightened the catalogue test's token-figure scan: any k-suffixed figure in a lever row now
  fails outright, and plain integers adjacent to the word token are caught in either order —
  closing the gap the fresh-context acceptance verifier flagged (a plain-integer figure could
  previously slip past the mechanical check). Verified against a seeded violation.

## [0.5.0]

### Added

- Three fix-path eval cases: mutation only on the explicit `fix` argument (a mid-report aside is
  not an override), user-global settings stay print-only inside the fix path with the auto-mode
  classifier caveat stated as the reason, and one-lever-at-a-time apply → re-measure → ledger
  with batch requests refused on attribution grounds. Eval file passes the evals-quality gate
  with zero warnings.

### Verified

- Acceptance sweeps recorded: the shipped plugin greps clean of every research-run figure
  (cite-never-transcribe), the catalogue contract test and hook contract test pass, and the
  skill-layout gate reports zero errors.

## [0.4.0]

### Added

- The guided fix path, behind the explicit `fix` argument only (the verb contract's mutation
  override): per-lever walkthrough over measurement-resolved `recommendable-on-fit` catalogue
  rows, scope-split write posture (project settings editable after per-diff approval;
  user-global `~/.claude/settings.json` print-only, never written; managed policy never
  targeted; env levers printed), and a mandatory one-lever-at-a-time
  apply → re-measure → compare → ledger loop.
- PreToolUse checkpoint hook (`hooks/settings-write-ask.mjs`, exec-form `node` invocation):
  returns `permissionDecision: "ask"` for any Write/Edit targeting a Claude Code settings
  surface, so auto mode prompts instead of silently approving — documented as a checkpoint, not
  a guarantee (PermissionRequest hooks, `disableAllHooks`, and the undocumented
  `bypassPermissions` interaction are named). Fail-open on internal error; kill switch shipped
  as `settings_write_ask_enabled` userConfig (default true) read via the hook-process mirror;
  hermetic contract test covers ask/silent/kill-switch/garbage/backslash paths.

## [0.3.0]

### Added

- The report contract (`skills/audit/reference/report.md`): stamped header, smart-zone headline
  (reclaimed reasoning space, never cost — with optional context-guard zone framing when that
  plugin is installed), measured category totals, ranked per-tool attribution with incomparable
  rows carrying reasons instead of numbers and unmeasured tools listed rather than omitted,
  lever findings grouped by honesty category with citations and emitted config, route-outs,
  degradations. Reports persist one-file-per-run under the keyed data directory.
- SKILL.md report step wiring the contract into the audit workflow as the default deliverable.

## [0.2.0]

### Added

- The lever catalogue (`skills/audit/reference/levers.json`): every known operator-controllable
  switch over the fixed startup payload as data rows — honesty category (six-term vocabulary with
  a dual-ledger request/context-window distinction), category basis, condition resolution by
  measurement, posture (recommendable / disclose-only / never-recommend / report-only),
  detection, measurement route, exact emitted config, official citations, verified date, and
  recheck trigger per row. Net-negative and unverified levers are structurally barred from the
  recommendable posture.
- Catalogue contract test (`levers.test.sh`): categories confined to the vocabulary, citations
  required, postures consistent, and no shipped token figures — the cite-never-transcribe rule
  made mechanical.
- SKILL.md lever-presentation step wiring the catalogue's honesty rules into the audit workflow.

## [0.1.0]

### Added

- Initial release: the measurement engine and the `audit` skill's measurement workflow.
- `skills/audit/scripts/measure.mjs` — SDK-primary meter over the Agent SDK's structured context
  usage (exact integers, live tool enumeration), degrading to a version-aware parser of headless
  `/context` output (display-rounded, refuses loudly on format drift) and then to a structured
  error with a remediation; per-tool attribution of the built-in tool pools by bare-name-deny A/B
  differencing with an optional additivity verification; enforced comparability rules
  (skill-listing signature, one mode, one binary version); offline `compare` producing ledger
  rows and a per-project ledger (one file per run plus an appended history line) under a
  caller-derived state-keyed data directory; every record stamped with the measured binary path
  and version, mode, precision, and session kind.
- `/context-budget:audit` — read-only measurement workflow: stamped baseline snapshot, attribution
  over the live tool list, before/after ledger loop; prints exact config
  (`permissions.deny` bare names) and applies nothing.
- `reference/engine.md` — record schemas, degradation ladder, mechanism citations, comparability
  rules.
- Hermetic engine test suite (`measure.test.sh`) over the parser, compare, and ledger surfaces.
- `lib/state-key.sh` adopted from the marketplace's shared per-project state-key cluster.
