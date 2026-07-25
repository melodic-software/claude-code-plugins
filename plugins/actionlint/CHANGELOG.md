# Changelog

All notable changes to the `actionlint` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

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

### Added

- **`stdin_read_timeout` declared in userConfig (#1134).** The shared hook lib reads
  `CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT`, but per current docs `--config <key=value>` sets
  only options "declared in the plugin's manifest" and `/plugin configure` offers declared
  options — so the knob was unreachable through native config surfaces for this plugin. Declared
  now (type/default/floor mirroring the claude-ops precedent); other hook plugins reusing the
  shared lib should declare it the same way. Decision recorded in the setup skill's new Gotchas.
- **`skills/setup` Gotchas surface (#1134).** Records the manifest-declaration requirement, the
  undocumented post-install `--config` behavior, and attributes the `-shellcheck=` deadlock
  rationale as the hook author's own observation (no matching upstream rhysd/actionlint issue as
  of 2026-07-23; the edit-time latency rationale stands on its own). Clears the skill-quality
  no-Gotchas WARN.

### Changed

- **Setup skill no longer asserts the undocumented `--config` fresh-install claim (#1134).**
  "only applies on a fresh install (ignored once installed)" appears nowhere in current official
  docs; the guidance now cites what the docs do say (`--config` is a `claude plugin install`
  flag for manifest-declared options), marks post-install behavior undocumented, and keeps the
  verified uninstall-then-install headless path.

## [0.6.0]

### Fixed

- **Membership guard removed — 8.3 short-form paths no longer silently skip the lint (#1133).**
  The hook parsed `file_path` through the shared lib's `hook::read_file_path`, whose
  `CLAUDE_PROJECT_DIR` membership guard compares realpath-normalized forms; GNU `realpath` under
  Git Bash does not expand Windows 8.3 short names, so a short-form `file_path` (the shape Claude
  Code's own scratchpad paths take) failed the prefix match and the hook exited silently — no
  lint, no notice, no telemetry. For an advisory PostToolUse linter the guard protects nothing
  (the tool already ran; the hook cannot block), so every false-negative is pure coverage loss.
  The hook now parses the path itself (existence check retained; the workflow-location filters
  still bound what gets linted); the synced shared lib is untouched for consumers that need the
  guard. Regression tests: a deliberately mismatched `CLAUDE_PROJECT_DIR` still lints, and a
  short-prefix 8.3 path still lints where the volume generates short names.
- **A failed `cd`/actionlint launch no longer reads as a clean pass (#1133).** The lint invocation
  discarded its exit status; a failed `cd` (or an actionlint exit ≥ 2 — invalid CLI, fatal, launch
  failure) produced empty output and fell through to the clean-workflow branch, emitting telemetry
  `status:"ok", findings:[]` indistinguishable from a real pass. Both now emit `status:"error"`
  (captured output as `data.findings`) and stay silent on the advisory channels. Covered by a
  stubbed exit-3 actionlint test.
- **`data.file` can no longer leak an absolute path (#1133).** When the repo-root prefix strip did
  not match (mount/symlink mismatch), the telemetry `data.file` silently carried the absolute
  path, violating the schema's repo-relative contract; it now degrades to the basename.
- **Test gap closed: `-pyflakes=` regression fixture (#1133).** Only `-shellcheck=` was exercised;
  a `shell: python` run-block fixture now pins the pyflakes integration off.

## [0.5.2]

### Fixed

- **Emitted telemetry `hook` id now matches the published schema.** The hook emitted
  `"actionlint"` on all three paths (skipped / findings / clean), but the envelope
  `hook` value is the hook-script basename and its schema is discovered at
  `data/<hook>.schema.json`. It now emits `"actionlint-check"`, matching
  `docs/conventions/hook-telemetry/data/actionlint-check.schema.json` and the
  README Implementers table. Producer-conformance fix only — the published
  envelope/data contract is unchanged.

## [0.5.1]

### Changed

- Sync of the shared `hook-utils.sh`: the git-option parser distinguishes `--config-env`
  (an env-var name) from `-c`/`--config` (an inline value), and a `--config-env` alias for
  a guarded subcommand is refused by shape rather than by resolving the environment
  variable's value (`#740`). No behavior change for this plugin — it does not inspect git
  config values; shipped so consumers receive the shared library update.

## [0.5.0]

### Added

- **`statusMessage` declared on the hook's `hooks.json` handler** (hook-observability
  convention, `docs/conventions/hook-observability/`): a spinner label ("Checking
  workflow with actionlint...") now shows while the hook runs. Config-only — no
  runtime behavior change.

## [0.4.2]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.4.1]

### Changed

- Hook stdin is read via the shared `hook::buffer_stdin` helper (bounded `read -t`,
  default 2s) instead of a bare `cat`, so a Windows Win32-pipe late-EOF stall can no
  longer hang the hook indefinitely. Empty or timed-out stdin exits as a skip, matching
  the existing empty-payload behavior.

## [0.4.0]

### Added

- **`/actionlint:setup` skill** (fleet conformance wave: a uniform check-centric
  setup contract across the hook plugins). `check` (default) is read-only — it
  reads the hook script as the single source of truth and probes each runtime
  prerequisite (Bash, `jq`, `actionlint`), the optional auto-discovered
  `.github/actionlint.yaml`, and the effective `actionlint_enabled` toggle,
  reporting a PASS/FAIL/INFO table with one remediation line per FAIL. `apply`
  re-runs `check` then points at the resolution for each finding. Every
  prerequisite is a `PATH` binary or the native toggle, so `apply` is
  guidance-only with no write path — it never installs packages and never
  modifies the repository, user settings, or the plugin cache.

## [0.3.1]

### Changed

- Shared `hook-utils.sh` resynced from the repository library (no behavior
  change in this plugin's hook).

## [0.3.0]

### Changed

- **Missing prerequisites now skip visibly** (prerequisite-visibility wave;
  doctrine: a silently skipped feature is a defect). When `actionlint` or `jq`
  is absent, the hook emits a once-per-session notice to both Claude
  (`additionalContext`) and the user (`systemMessage`) instead of a silent
  no-op, then still exits `0` (advisory, never blocking). Notice dedup state
  lives under `${CLAUDE_PLUGIN_DATA}/skip-notices`.
- Shared `hook-utils.sh` resynced with the new prerequisite-visibility helpers
  (jq-free notice emitters, once-per-session gate, jq gate).
- README now declares the full hook runtime: Bash (Git Bash on native Windows),
  `jq`, and `actionlint`, each with its absence behavior.

## [0.2.0]

### Changed

- **Kill switch migrated to native `userConfig`** (the fleet-wide kill-switch
  doctrine ruling). The hook toggle is now the `actionlint_enabled` boolean
  (default `true`), read by the hook through the native
  `CLAUDE_PLUGIN_OPTION_ACTIONLINT_ENABLED` hook-process mirror. Configure
  interactively with `/plugin configure actionlint` or headless via
  `claude plugin install --config KEY=VALUE`.
- **BREAKING:** the `HOOK_ACTIONLINT_ENABLED` environment variable is retired
  and no longer read. A consumer that set it in a settings `env` block must
  re-express the value as the matching `userConfig` option. Zero-config behavior is unchanged (hook on, same
  defaults). The `HOOK_TELEMETRY_SINK` consumer-side telemetry seam is
  unaffected.
