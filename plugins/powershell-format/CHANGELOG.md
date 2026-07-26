# Changelog

All notable changes to the `powershell-format` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.6.0]

### Security

- **Code-loading analyzer settings are now gated on explicit approval.** A
  `PSScriptAnalyzerSettings.psd1` that declares `CustomRulePath` makes
  PSScriptAnalyzer load and execute repository-supplied rule modules during
  analysis, so the hook no longer runs the formatter/analyzer under such a
  settings file automatically: it skips the run — with a visible
  once-per-session notice on both channels — until the user approves that exact
  settings-and-rule-module content state by creating the marker directory named
  in the notice (under `${CLAUDE_PLUGIN_DATA}/trust-approvals`). The approval
  signature is content-addressed over the settings file AND every file
  reachable under each declared `CustomRulePath` entry (recursively for
  directories), plus every repository file those files reference by string
  literal (transitively, bounded — a leaf module's dot-sourced or imported
  dependencies execute with it; the standard `$PSScriptRoot/...` self-relative
  prefix is expanded against the containing module directory), so a change to
  the settings or to any referenced rule module —
  e.g. a branch switch swapping module bytes under an unchanged settings file —
  revokes the approval. The gate fails closed when `CLAUDE_PLUGIN_DATA` is
  unavailable, and also when a `CustomRulePath` entry does not resolve to
  hashable content: an unpinnable state offers no approval route at all.
  Detection uses PowerShell's restricted data-file parser
  (`Import-PowerShellDataFile`), not a textual scan, so quoting/escape
  obfuscation of the key cannot evade it — and a settings file the restricted
  parser rejects stays gated rather than run, since it cannot be proven
  code-free. Previously the hook ran the analyzer unconditionally, so a
  malicious repository's checked-in settings could execute arbitrary PowerShell
  on a routine `.ps1`/`.psm1`/`.psd1` edit. Settings without `CustomRulePath`
  are unaffected. The edit itself is still never blocked — the hook always
  exits 0.

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
