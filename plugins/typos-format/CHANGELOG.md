# Changelog

All notable changes to the `typos-format` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.4.0]

### Fixed

- **Every correction the hook applies is now disclosed on both channels.** On the
  all-fixed path the hook emitted nothing at all — no `additionalContext`, no
  `systemMessage`, telemetry only — so a rewrite drawn from typos' built-in
  dictionary reached the file with the only trace being the harness's generic
  "a PostToolUse hook modified this file" notice: no hook name, no word, no
  diff. An acronym or identifier the dictionary maps to an unrelated English
  word was therefore corrupted invisibly, indistinguishably from a benign
  reformat. The hook now reports each applied rewrite — token, replacement, and
  line — to Claude via `additionalContext` and to the user via `systemMessage`,
  capped at ten per run with a count of the remainder so the disclosure cannot
  itself become a context flood.
- **The allow-list remediation moved onto the applied-correction path.** The
  "if intentional, add it to `extend-words` / `extend-identifiers`" guidance sat
  only on the residual branch, so it never fired for the corrections that
  actually change file content — the one case where it is load-bearing. A
  dictionary autocorrect has no memory: a word repaired by hand is rewritten
  again on the next edit until the repo allow-lists it, and until now nothing
  said so.

### Added

- **`typos_format_write_changes` userConfig (default `true`).** Set it to
  `false` for a report-only hook: findings are reported and no file is
  modified. Read from the `CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_WRITE_CHANGES`
  environment mirror, because shell-form hook commands reject
  `${user_config.*}` substitution outright.
- **`data.applied` on the telemetry envelope** — the corrections this run wrote,
  as `{typo, correction, line}`. Additive; `data.findings` keeps its existing
  residual-only meaning and shape.
- **`/typos-format:setup check` reports the effective write mode.** The setup
  skill described a single tunable and probed only `typos_format_enabled`, so
  with `typos_format_write_changes=false` it could report the hook fully
  operational to a user who invoked it precisely because spell-fixing was not
  happening. Write mode is now a reported INFO row with its own remediation —
  including the alternative that usually fits better, allow-listing the specific
  words rather than turning every correction off.
- **Stub-driven contract tests for the disclosure surface.** The suite
  previously skipped in full when no `typos` binary was installed, which is the
  CI runner's state — so nothing about this hook was gated there. The
  disclosure, report-only, cap, and telemetry cases now run against a stub
  binary and execute everywhere; the config-discovery and exclusion cases still
  require a real `typos`.

### Changed

- **The hook now scans read-only before it writes.** `typos --write-changes`
  emits nothing for a correction it applies (verified against typos-cli 1.44.0:
  a fully-fixable file exits 0 with empty stdout after rewriting), so a
  write-only run has no information about what it changed. A read-only pass
  captures the pre-write finding set; the applied set is derived as scan minus
  what survived the write, rather than by guessing which findings typos
  considers safe to auto-fix. Cost is one extra typos invocation only on files
  that actually have findings — measured at roughly 80 ms on a 68 KB file,
  against the handler's 15-second timeout. The read-only pass runs first, so a
  run killed at the timeout between the two passes has modified nothing.
  Both passes are guarded identically: an exit 2 with no output is a typos break,
  not an empty residual set, so a write that broke mid-run is reported as a tool
  break instead of being read as "every finding was applied".
- **Classification is one `jq` pass, not a shell loop.** Process-spawn cost, not
  typos, dominates this hook, and a per-finding loop turns a heavily-corrected
  file into the very defect being fixed: the file is rewritten, the handler's
  15-second timeout fires, and stdout is empty — silent mutation again, on
  exactly the files where the disclosure matters most. The scan set, the
  residual set, the split between them, and the capped display text are all
  produced by a single invocation, so the subprocess count is constant in the
  number of findings. Both finding sets reach `jq` on **stdin**, never as
  `--arg` values: Windows caps a process command line at 32767 characters and
  typos' jsonlines run about 110 bytes per finding, so an argument-passed set
  broke silently somewhere past ~300 corrections — jq never ran and the hook
  degraded to "could not be summarized" on precisely the typo-heavy files the
  disclosure matters most for. A 500-correction file (past that limit, and the
  scale at which the old per-finding loop timed out) is asserted to disclose all
  500 inside the budget; it runs in about 3 seconds against the real binary. The
  residual key is built and compared as a JSON string inside `jq`, so a token
  carrying a shell or glob metacharacter is data throughout.
- **Residual membership is a hash lookup, not a linear scan.** Classifying with
  `index` over an array is quadratic exactly when the residual set is large — a
  minified or generated file where most findings are ambiguous. Measured: 10,000
  all-residual findings took about 15.7 s inside `jq` alone, past the handler's
  15-second timeout, and the file is rewritten *before* classification runs, so
  that timeout lands after the mutation and before any disclosure. The same set
  takes about 0.6 s keyed by object. The scale cases now cover an all-applied
  AND an all-residual set: the applied path alone never touches that branch.
- **The telemetry payload reaches `jq` on stdin too.** `data.findings` and the
  new `data.applied` are uncapped, so roughly a thousand ordinary corrections
  (about 45 KB of JSON) exceeded the same command-line ceiling and the fallback
  would have emitted an envelope reporting `applied: []` for a file this hook
  had just rewritten. A dropped envelope is inside the best-effort telemetry
  contract; one that arrives claiming a heavily-rewritten file was untouched is
  not. The shared `hook::emit_telemetry` still hands the finished payload over
  as an argument (#1595), so an oversized envelope is currently dropped rather
  than delivered — the correct failure direction, and what the scale assertion
  pins.
- Carriage returns no longer leak into the emitted report. `jq` writes stdout in
  text mode on Windows, so a multi-line value returns CRLF-terminated and
  command substitution strips only the last one, leaving a literal `\r` before
  every remaining newline in the escaped context.

## [0.3.4]

### Changed

- **Test scaffolding: migrated `mktemp -p` temp file/dir creation to the portable `mktemp "$DIR/template"` form.** BSD/macOS `mktemp` has no `-p` flag; the directory now rides in the positional TEMPLATE argument instead, which both GNU and BSD `mktemp` accept identically. Test-only — no hook behavior change. Part of #1527 (`typos-format.test.sh`).

## [0.3.3]

### Fixed

- **Shared `hook-utils.sh`: a bare or trailing unquoted `NAME=value` Bash
  command no longer leaks the assignment value into the privacy-safe
  telemetry/audit subject.** `hook::extract_bash_subject` stripped a leading
  `VAR=value` prefix only when a following command word consumed it, so a
  command whose LAST token was an unquoted assignment (e.g. `TOKEN=ghp_…`)
  survived to the subject and emitted `Bash:TOKEN=ghp_…` into
  `hook-events.jsonl` and any wired `HOOK_TELEMETRY_SINK`. A resolved token
  still shaped like a shell assignment now bails to the bare `Bash` subject,
  matching the existing quoted-value bail (`VAR=x cmd` still reduces to
  `Bash:cmd`). Synced from `lib/hook-utils.sh`; the subject is
  telemetry/audit-only, so no guard or formatter block/allow behavior changes.

## [0.3.2]

### Fixed

- **Headless reconfigure recipe now preserves install scope (#1406).** The `claude plugin
  uninstall` → `claude plugin install ... --config` recipe in `skills/setup/SKILL.md` defaulted
  both halves to `-s user`. When this plugin is installed at `project` or `local` scope, that
  silently uninstalled a separate user-scope record while the effective project/local install kept
  loading, and the reinstall landed at a scope that does not load. Both commands now carry
  `-s <scope>`, sourced from what `claude plugin list` reports for this plugin — the same fix
  already applied to `session-flow` and `rate-limit-guard` in #1393.

## [0.3.1]

### Changed

- Sync of the shared `hook-utils.sh`: the git-option parser distinguishes `--config-env`
  (an env-var name) from `-c`/`--config` (an inline value), and a `--config-env` alias for
  a guarded subcommand is refused by shape rather than by resolving the environment
  variable's value (`#740`). No behavior change for this plugin — it does not inspect git
  config values; shipped so consumers receive the shared library update.

## [0.3.0]

### Added

- **`statusMessage` declared on the hook's `hooks.json` handler** (hook-observability
  convention, `docs/conventions/hook-observability/`): a spinner label ("Fixing
  typos...") now shows while the hook runs. Config-only — no runtime behavior
  change.

## [0.2.0]

### Changed

- **Removed the opt-in config-gate.** The hook now runs `typos --write-changes`
  unconditionally on every `Write`/`Edit`, matching `markdown-format`'s existing
  unconditional pattern — typos ships a built-in spelling dictionary and needs
  no configuration to be useful. Previously the hook silently no-op'd on any
  repo without a hand-authored `typos.toml`/`_typos.toml`/`.typos.toml`/
  `Cargo.toml`/`pyproject.toml`, defeating the plugin's zero-config auto-fix
  purpose on exactly the repos it was meant to help. A consumer typos config,
  when present, is still discovered and honored automatically by typos itself
  (allowlist/exclude) — this hook never re-implemented that discovery and
  still doesn't; only the activation gate is removed.

## [0.1.0]

### Added

- Initial release: a `PostToolUse` hook that runs `typos --write-changes` on
  `Write`/`Edit` of any file, gated on a consumer typos config
  (`typos.toml`/`_typos.toml`/`.typos.toml`/`Cargo.toml`/`pyproject.toml`)
  found by an ancestor walk-up, mirroring the `ruff-format`/`markdown-format`
  plugin pattern. Residual (unfixable) findings surface via `additionalContext`
  with remediation guidance pointing at `extend-words` / `extend-identifiers` /
  `extend-ignore-re` allowlist entries. Advisory only — never blocks the edit.
- `hook-telemetry` conformance: emits a schema-valid envelope
  (`docs/conventions/hook-telemetry/data/typos-format.schema.json`) via the
  shared `hook::emit_telemetry` helper.
- `/typos-format:setup check|apply` skill for prerequisite verification.
