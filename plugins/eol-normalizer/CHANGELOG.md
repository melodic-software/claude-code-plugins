# Changelog

All notable changes to the `eol-normalizer` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.5.5]

### Fixed

- **Shared `hook-utils.sh`: a large tool payload no longer makes this plugin's hooks silently
  skip (#1563).** `hook::buffer_stdin` read the hook payload with `read -d ''`, which consumes a
  pipe one byte at a time (~32 KB/s on Git Bash), so the `stdin_read_timeout` bound was really a
  ~64 KB throughput ceiling rather than the stall detector it was written to be. Past that ceiling
  the read returned a truncated payload and rc 1, and this plugin's hooks took their `|| exit 0`
  branch — the hook did not run at all, with no diagnostic, on exactly the large writes it was
  most wanted for. The read is now chunked (`read -N`), which bash satisfies with block reads, and
  the bound became an idle bound that arms per chunk: a read still making progress is never cut
  off, while a pipe that goes silent for `stdin_read_timeout` seconds still stops the read the
  same way. Measured: 50 KB drops from ~2100 ms to ~20 ms, 200 KB from ~6800 ms to ~85 ms. Synced
  from `lib/hook-utils.sh`; this plugin's own hook behavior is otherwise unchanged.

## [0.5.4]

### Changed

- **Test scaffolding: migrated `mktemp -p` temp file/dir creation to the portable `mktemp "$DIR/template"` form.** BSD/macOS `mktemp` has no `-p` flag; the directory now rides in the positional TEMPLATE argument instead, which both GNU and BSD `mktemp` accept identically. Test-only — no hook behavior change. Part of #1527 (`eol-normalizer.test.sh`).

## [0.5.3]

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

## [0.5.2]

### Fixed

- **Headless reconfigure recipe now preserves install scope (#1406).** The `claude plugin
  uninstall` → `claude plugin install ... --config` recipe in `skills/setup/SKILL.md` defaulted
  both halves to `-s user`. When this plugin is installed at `project` or `local` scope, that
  silently uninstalled a separate user-scope record while the effective project/local install kept
  loading, and the reinstall landed at a scope that does not load. Both commands now carry
  `-s <scope>`, sourced from what `claude plugin list` reports for this plugin — the same fix
  already applied to `session-flow` and `rate-limit-guard` in #1393.

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
  convention, `docs/conventions/hook-observability/`): a spinner label ("Normalizing
  line endings...") now shows while the hook runs. Config-only — no runtime behavior
  change.

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

- **`/eol-normalizer:setup` skill** (fleet conformance wave, dim 8). A uniform check-centric
  setup contract: `check` (default, read-only) reads both the hook and its sourced
  `normalize-eol.sh` library as the single source of truth and reports a PASS/FAIL/INFO table
  for Bash, `jq`, `git` (FAIL when absent — the hook silently no-ops without it, so the check
  is the only visibility), the governing `.gitattributes` `eol=` policy, and the
  `eol_normalizer_enabled` toggle. `apply` is idempotent and pure guidance — every
  prerequisite is a system tool, so it installs nothing and writes nothing (never
  `.gitattributes`).

## [0.3.1]

### Changed

- Shared `hook-utils.sh` resynced from the repository library (no behavior
  change in this plugin's hook).

## [0.3.0]

### Changed

- **Missing jq now skips visibly** (prerequisite-visibility wave; doctrine: a
  silently skipped feature is a defect). Without `jq` the hook cannot parse its
  input, so it now surfaces a once-per-session notice to both Claude
  (`additionalContext`) and the user (`systemMessage`) instead of silently
  disabling normalization. Notice dedup state lives under
  `${CLAUDE_PLUGIN_DATA}/skip-notices`.
- Shared `hook-utils.sh` resynced with the new prerequisite-visibility helpers
  (jq-free notice emitters, once-per-session gate, jq gate).
- README now declares the full hook runtime: Bash (Git Bash on native Windows),
  `jq`, and git, with the no-git-repo case classified as a quiet not-applicable
  rather than a missing prerequisite.

## [0.2.0]

### Changed

- **Kill switch migrated to native `userConfig`** (the fleet-wide kill-switch doctrine
  ruling). The hook's toggle is now the `eol_normalizer_enabled` boolean (default `true`),
  read by the hook through the native `CLAUDE_PLUGIN_OPTION_EOL_NORMALIZER_ENABLED`
  hook-process mirror. Configure interactively with `/plugin configure eol-normalizer`
  or headless via `claude plugin install --config KEY=VALUE`.
- **BREAKING:** the `HOOK_EOL_NORMALIZER_ENABLED` environment variable is retired
  and no longer read. A consumer that set it in a settings `env` block must
  re-express the value as the matching `userConfig` option.
  Zero-config behavior is unchanged (normalization on, same defaults). The
  `HOOK_TELEMETRY_SINK` consumer-side telemetry seam is unaffected.
