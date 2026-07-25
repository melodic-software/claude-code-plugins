# Changelog

All notable changes to the `powershell-format` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.5.2]

### Added

- **`hook::jq_fields` in the shared hook lib (#1345).** Extracts N jq fields in ONE `jq` process
  instead of N `printf | jq | tr` pipelines, returning them in `HOOK_JQ_FIELDS`. Values are joined on
  U+001E, which jq strips from each value first so payload text can never shift field alignment. This
  plugin's own hooks do not call it yet; it arrives with the shared-lib sync.

### Fixed

- **Two process spawns removed from every hook invocation (#1345).** `hook::buffer_stdin` stripped CR
  with `$(printf '%s' "$input" | tr -d '\r')`; it now uses parameter expansion. On Windows, where
  `fork` emulation makes each spawn cost hundreds of milliseconds, that command substitution was the
  largest fixed cost paid by every hook in this plugin on every matching tool call. The buffered
  payload — including the trailing-newline trim a command substitution performed implicitly — is
  byte-identical. Carried in via `scripts/sync-hook-utils.sh`; no behavior of this plugin changed.

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
  convention, `docs/conventions/hook-observability/`): a spinner label ("Formatting
  PowerShell...") now shows while the hook runs. Config-only — no runtime behavior
  change.

## [0.4.3]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.4.2]

### Changed

- Hook stdin is read via the shared `hook::buffer_stdin` helper (bounded `read -t`,
  default 2s) instead of a bare `cat`, so a Windows Win32-pipe late-EOF stall can no
  longer hang the hook indefinitely. Empty or timed-out stdin exits as a skip, matching
  the existing empty-payload behavior.

## [0.4.1]

### Changed

- **Quiet pwsh-absent skip documented at the site** with a `silent-skip-ok`
  annotation (the marketplace's new silent-skip CI gate). No behavior change:
  absent `pwsh` remains a by-design not-applicable quiet skip, still recorded
  via opt-in telemetry.

## [0.4.0]

### Added

- **`/powershell-format:setup` skill** (fleet conformance wave: a uniform
  check-centric setup contract across the hook plugins). `check` (default) is
  read-only — it reads the hook script as the single source of truth and probes
  each runtime prerequisite (Bash, `jq`, `pwsh` 7+, the PSScriptAnalyzer module),
  the `PSScriptAnalyzerSettings.psd1` opt-in, and the effective
  `powershell_format_enabled` toggle, reporting a PASS/FAIL/INFO table with one
  remediation line per FAIL. It preserves the plugin's deliberate asymmetry: only
  `jq` absence is a FAIL, while absent `pwsh` / module / settings file are
  by-design not-applicable INFO. The module and settings probes surface the
  README trust boundary (a settings file's `CustomRulePath` runs during
  analysis). `apply` re-runs `check` then points at the resolution for each
  finding — `pwsh` install and `Install-Module PSScriptAnalyzer` are user-scope
  guidance only, never run. `apply` is guidance-only with no write path — it
  never installs anything and never modifies the repository (including
  `PSScriptAnalyzerSettings.psd1`), user settings, or the plugin cache.

## [0.3.1]

### Changed

- Shared `hook-utils.sh` resynced from the repository library (no behavior
  change in this plugin's hook).

## [0.3.0]

### Changed

- **Missing jq now skips visibly** (prerequisite-visibility wave; doctrine: a
  silently skipped feature is a defect). Without `jq` the hook cannot parse its
  input, so it now surfaces a once-per-session notice to both Claude
  (`additionalContext`) and the user (`systemMessage`) instead of a silent
  no-op. `pwsh`/PSScriptAnalyzer absence deliberately stays quiet — a machine
  without PowerShell is classified as not-applicable, and the README now says
  so. Notice dedup state lives under `${CLAUDE_PLUGIN_DATA}/skip-notices`.
- Shared `hook-utils.sh` resynced with the new prerequisite-visibility helpers
  (jq-free notice emitters, once-per-session gate, jq gate).

## [0.2.0]

### Changed

- **Kill switch migrated to native `userConfig`** (the fleet-wide kill-switch doctrine
  ruling). The hook toggle is now the `powershell_format_enabled` option (default `true`),
  read by the hook through the native `CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_ENABLED`
  hook-process mirror. Configure interactively with `/plugin configure powershell-format`
  or headless via
  `claude plugin install --config KEY=VALUE`.
- **BREAKING:** the `HOOK_POWERSHELL_FORMAT_ENABLED` environment variable is
  retired and no longer read. A consumer that set it in a settings `env` block
  must re-express the value as the matching `userConfig` option.
  Zero-config behavior is unchanged (hook on, same defaults). The `HOOK_TELEMETRY_SINK`
  consumer-side telemetry seam is unaffected.
