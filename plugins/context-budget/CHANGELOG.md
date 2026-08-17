# Changelog

All notable changes to the `context-budget` plugin.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
