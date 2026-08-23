# Changelog

All notable changes to the `context-budget` plugin.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.6.6]

### Fixed

- **Engine:** the additivity verifier no longer coerces a null bucket delta to `0`. A combined
  deny can empty `System tools` or `System tools (deferred)` out of the snapshot; the snapshot
  comparison correctly records that bucket's delta as `null`, but the verifier summed it with
  `?? 0` and published a fabricated `combinedSaved: 0` as `comparable: true`. The additivity
  record (and each per-tool row, which had the same coercion) now reports the saving as `null`
  with `comparable: false` and a reason naming the vanished bucket
  ([#3197](https://github.com/melodic-software/claude-code-plugins/issues/3197)). A bucket
  absent from *both* runs remains a non-event — outside that binary's category vocabulary, not
  a missing measurement. In sdk mode, where numbers are exact and the category vocabulary is
  known, an omitted bucket is now recorded as an explicit `0` at snapshot time, so a combined
  deny that empties a bucket yields a real measured delta instead of an incomparable record.
  Every synthesized zero is named in the snapshot's `caveats[]` so a standalone
  `snapshot`/`compare`/`ledger` consumer can tell a reported 0 from a filled-in omission; the
  vanish/`comparable: false` path remains cli-parse only.

## [0.6.5]

### Changed

- **setup:** normalized restated setup-contract prose (preamble, probe-ladder
  opening, never-writes boundary, and/or headless-reconfigure recipe as present) to the
  canonical fleet wording, keeping the operable text inline with a provenance-only citation
  (whole-repo extract-ssot batch, #2698).

## [0.6.4]

### Fixed

- **Docs:** the generated options block's headless route no longer implies `--config` applies
  only at install time, and now carries the CLI version its claim was verified against
  ([#3111](https://github.com/melodic-software/claude-code-plugins/issues/3111)). The block also
  now separates the write from its effect: the value is stored immediately, but hooks are handed
  their `CLAUDE_PLUGIN_OPTION_*` at session start, so a check run in the same session still
  reports the old value and that is not a failed write. Two upstream links that pointed at empty
  backward-compatibility anchors on the settings page were repointed at the headings that hold
  the content.

### Added

- **`/context-budget:setup`** — the plugin declared `userConfig` but shipped no setup skill.
  Adds the fleet's uniform check/apply contract: `check` verifies what the native configuration
  prompt cannot, `apply` routes a reconfiguration and then reads the effective value back before
  reporting it ([#3111](https://github.com/melodic-software/claude-code-plugins/issues/3111)).

## [0.6.3]

### Fixed

- **Security:** the settings-write ask checkpoint matches paths case-insensitively. macOS and
  Windows filesystems resolve `.claude/Settings.json` to the same file as the lowercase name, so
  the previous case-sensitive match let a differently-cased write bypass the checkpoint silently
  on exactly the platforms it supports (PR security-review finding). Case-variant regression
  cases added to the hook contract test.

## [0.6.2]

### Fixed

- `--out` creates missing parent directories, so a fresh audit's first snapshot no longer
  discards an expensive measurement with ENOENT on the not-yet-created data dir (PR review
  finding).
- The `systemToolsComparable` predicate now includes every mismatch it records as a reason:
  binary path (same version, different install) and a moved Skills bucket under a matching
  listing both mark the comparison incomparable instead of warning while publishing the delta
  (PR review finding). Tests added for all three cases.

## [0.6.1]

### Fixed

- README carries the generated options reference for `settings_write_ask_enabled` (owed since
  the option shipped in 0.4.0; `scripts/sync-plugin-options-docs.py` gate).

- Ledger run IDs are collision-safe: a same-second rerun of the same lever (or a re-appended
  row) now lands in a numbered-suffix run file instead of silently overwriting the earlier one —
  the one-file-per-run contract held only by luck before (PR review finding). Test added.
- Windows command shims spawn correctly: binary resolution now prefers `claude.exe` over
  `claude.cmd`, and a `.cmd`/`.bat` shim is executed through the shell (Node cannot spawn
  command shims directly), so shim-only Windows installs measure instead of degrading
  (PR review finding). Untested on real Windows hardware — recorded as a manual-verification
  gap, matching the repo's convention.

## [0.6.0]

### Changed

- Empirical hardening from the first end-to-end shakedown and two fresh-context probes
  (v2.1.232, headless):
  - cli-parse `totalTokens` now excludes every `... (deferred)` category, not only the built-in
    one — HTTP MCP tools measured deferred in their own `MCP tools (deferred)` category
    (anthropics/claude-code#40314's upfront loading did not reproduce), and the headline must
    exclude both pools in both modes; engine.md's headline rule updated to match.
  - The ask-checkpoint's undocumented-`bypassPermissions` caveat upgraded to a measurement: at
    v2.1.232 headless the `ask` fires and blocks even under `bypassPermissions` (surfacing as a
    tool error carrying the reason); interactive behavior stays explicitly unmeasured. Hook
    header and SKILL.md fix-path wording updated.
  - New deny-bare-tool caveat: denying the tool-search tool is a measured anti-lever (it forces
    the entire deferred pool upfront); measure any infrastructure tool before recommending its
    deny. The tool-search-deferral row now records the dedicated MCP deferred bucket.

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
