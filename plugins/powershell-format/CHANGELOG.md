# Changelog

All notable changes to the `powershell-format` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.6.3]

### Fixed

- **Shared `hook-utils.sh`: an in-project file spelled as a Windows 8.3 short name is no longer
  silently skipped (#1636).** `hook::physical_path` canonicalized with GNU realpath, which under
  Git Bash resolves symlinks but leaves 8.3 short names (`KYLESE~1`) unexpanded, so a short-form
  `file_path` — the shape Claude Code's own scratchpad paths take — failed the
  `CLAUDE_PROJECT_DIR` prefix comparison in `hook::read_file_path` and the hook skipped the file
  silently: no lint, no notice, no telemetry. The lib now expands short names on Windows/MSYS
  hosts (new `hook::expand_8dot3`, via `cygpath -l`) before the comparison, and only when the
  expanded form actually differs — a legitimate long name containing `~` passes through
  untouched, and a genuinely out-of-project file is still skipped: that defense-in-depth scoping
  is deliberate and preserved. 8.3 generation is a per-volume property (`fsutil 8dot3name
  query`), so the defect was live only for checkouts on a volume that generates short names —
  and invisible to contributors whose checkouts sit on one that does not. This plugin's own
  `hook::physical_path` call sites — the settings-walk anchors and ceiling — see the same
  expansion, keeping the walk consistent with the membership guard's verdict for short-form
  paths. Synced from `lib/hook-utils.sh`.

## [0.6.2]

### Fixed

- **Shared `hook-utils.sh`: a large tool payload no longer makes this plugin's hooks silently
  skip (#1563).** `hook::buffer_stdin` read the hook payload with `read -d ''`, which consumes a
  pipe one byte at a time (~32 KB/s on Git Bash), so the `stdin_read_timeout` bound was really a
  ~64 KB throughput ceiling rather than the stall detector it was written to be. Past that ceiling
  the read returned a truncated payload and rc 1, and this plugin's hooks took their `|| exit 0`
  branch — the hook did not run at all, with no diagnostic, on exactly the large writes it was
  most wanted for. The read is now chunked (`read -N`), which bash satisfies with block reads, and
  the bound became a true idle bound: `read -t` is a deadline for the whole requested read rather
  than an inactivity timer, so a timed-out read that nevertheless returned bytes is now treated as
  progress — its partial chunk is kept and a fresh window is armed. Only a window that delivers
  nothing at all is a stall. `read -N` is Bash 4.1+, and these hooks support Bash 3.2+ (macOS
  system bash), so the pre-4.1 path falls back to the delimiter read inside the same re-arming
  loop. Measured: 50 KB drops from ~2100 ms to ~20 ms, 200 KB from ~6800 ms to ~85 ms. Synced
  from `lib/hook-utils.sh`; this plugin's own hook behavior is otherwise unchanged.

## [0.6.1]

### Changed

- **Test scaffolding: migrated `mktemp -p` temp file/dir creation to the portable `mktemp "$DIR/template"` form.** BSD/macOS `mktemp` has no `-p` flag; the directory now rides in the positional TEMPLATE argument instead, which both GNU and BSD `mktemp` accept identically. Test-only — no hook behavior change. Part of #1527 (`powershell-format.test.sh`).

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
  dependencies execute with it; `$PSScriptRoot` and `$PSCommandPath` are
  expanded wherever they appear in the reference, not only as a leading prefix,
  so the standard interpolated dependency form pins instead of dropping out of
  the signature), so a change to
  the settings or to any referenced rule module —
  e.g. a branch switch swapping module bytes under an unchanged settings file —
  revokes the approval. The gate fails closed when `CLAUDE_PLUGIN_DATA` is
  unavailable, and also when a `CustomRulePath` entry does not resolve to
  hashable content: an unpinnable state offers no approval route at all.
  A load whose TARGET cannot be pinned to a file is refused the same way — a
  variable, an env lookup, a composed expression such as
  `. (Join-Path $PSScriptRoot "deps" "helper.ps1")`, or an interpolated string
  holding any other variable. That verdict comes from PowerShell's own parser
  (`Parser::ParseInput`, examining every `.`/`&` invocation and
  `Import-Module`/`Add-Type`/`Invoke-Expression`-class command) rather than from
  a text pattern, so it cannot be evaded by quoting or comment placement and
  needs no file-extension guessing — the extensionless
  `Import-Module "$root/MyModule"` form is caught without one. A loader fed by a
  PIPELINE is refused too: it takes its source from the upstream element rather
  than from its own arguments, so `Get-Content (Join-Path $PSScriptRoot deps
  helper.ps1) -Raw | Invoke-Expression` would otherwise present nothing but a
  constant command name to inspect. A target the
  parser accepts is pinned from the parser too, not left to the quoted-literal
  scan: PowerShell does not require quotes around a command argument, so
  `. $PSScriptRoot\helper.ps1` would otherwise be judged pinnable and then never
  pinned. `using module <path>` and `using assembly <path>` are collected as well
  — both are `UsingStatementAst` nodes rather than commands, so neither the
  command walk nor a text scan would see them, and an assembly directive loads a
  repository DLL exactly as a module directive loads a `.psm1`. An assembly the
  parser cannot load is reported as a parse error, which already refuses
  approval, so both directions are closed: loadable is pinned, unloadable is
  unverifiable. `using namespace` and `using type` name no repository file and are
  left alone. An extensionless reference resolves through
  PowerShell module resolution, so the `.psd1`/`.psm1`/`.ps1`/`.dll` candidates
  and both directory layouts — `MyModule/MyModule.psd1` and the versioned
  `MyModule/<version>/MyModule.psd1` — are all pinned rather than only an exact
  leaf. An inline script block is exempt because it is part of the
  already-hashed file, and a composed load nested inside it is still judged on
  its own.
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
