# Changelog

All notable changes to the `bash-format` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.6.7]

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
  and invisible to contributors whose checkouts sit on one that does not. Synced from
  `lib/hook-utils.sh`.

## [0.6.6]

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

## [0.6.5]

### Changed

- **Test scaffolding: migrated `mktemp -p` temp file/dir creation to the portable `mktemp "$DIR/template"` form.** BSD/macOS `mktemp` has no `-p` flag; the directory now rides in the positional TEMPLATE argument instead, which both GNU and BSD `mktemp` accept identically. Test-only — no hook behavior change. Part of #1527 (`bash-format.test.sh`).

## [0.6.4]

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

## [0.6.3]

### Fixed

- **Headless reconfigure recipe now preserves install scope (#1406).** The `claude plugin
  uninstall` → `claude plugin install ... --config` recipe in `skills/setup/SKILL.md` defaulted
  both halves to `-s user`. When this plugin is installed at `project` or `local` scope, that
  silently uninstalled a separate user-scope record while the effective project/local install kept
  loading, and the reinstall landed at a scope that does not load. Both commands now carry
  `-s <scope>`, sourced from what `claude plugin list` reports for this plugin — the same fix
  already applied to `session-flow` and `rate-limit-guard` in #1393.

## [0.6.2]

### Changed

- **Documented the project scope.** When `CLAUDE_PROJECT_DIR` is set, the hook acts only on shell
  files under it (symlink-resolved membership guard in the shared library); a `.sh`/`.bash` file
  written outside the project is silently skipped. When `CLAUDE_PROJECT_DIR` is unset (e.g. some
  headless `-p` sessions) the guard is skipped and any existing edited file is processed. README
  gains a "Scope" note and the setup skill's `check` gains a project-scope probe (and no longer
  reports "fully operational" without the caveat) so an advisory linter's out-of-project no-op is
  not a surprise (`#1168`, finding F1; scope-qualification per PR review).
- Setup skill: added a `## Gotchas` section (cache-path `ENAMETOOLONG`, `check`-PASS-≠-full-coverage,
  opt-in-conditional `shfmt` FAIL) (`#1168`, finding F6).

### Tests

- `bash-format.test.sh`: added coverage for the `[*.{sh,bash}]` brace-list and `[**/*.sh]`
  path-prefixed `.editorconfig` opt-in forms, and for the `shfmt < 3.8` `--apply-ignore` fallback
  (`|| shfmt -w`) via a stub shfmt (`#1168`, finding F2). No runtime behavior change.

## [0.6.1]

### Changed

- Sync of the shared `hook-utils.sh`: the git-option parser distinguishes `--config-env`
  (an env-var name) from `-c`/`--config` (an inline value), and a `--config-env` alias for
  a guarded subcommand is refused by shape rather than by resolving the environment
  variable's value (`#740`). No behavior change for this plugin — it does not inspect git
  config values; shipped so consumers receive the shared library update.

## [0.6.0]

### Added

- **`statusMessage` declared on the hook's `hooks.json` handler** (hook-observability
  convention, `docs/conventions/hook-observability/`): a spinner label ("Formatting
  shell script...") now shows while the hook runs. Config-only — no runtime
  behavior change.

## [0.5.2]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.5.1]

### Changed

- Hook stdin is read via the shared `hook::buffer_stdin` helper (bounded `read -t`,
  default 2s) instead of a bare `cat`, so a Windows Win32-pipe late-EOF stall can no
  longer hang the hook indefinitely. Empty or timed-out stdin exits as a skip, matching
  the existing empty-payload behavior.

## [0.5.0]

### Added

- **`/bash-format:setup` skill** (fleet conformance wave: a uniform check-centric
  setup contract across the hook plugins). `check` (default) is read-only — it
  reads the hook script as the single source of truth and probes each runtime
  prerequisite (Bash, `jq`, ShellCheck for the lint pass, shfmt for the format
  pass), the `.editorconfig` shell opt-in that gates formatting (mirroring the
  hook's `shell_editorconfig_opt_in` logic — a section governing shell files,
  not merely a present `.editorconfig`), the auto-discovered `.shellcheckrc`, and
  the effective `bash_format_enabled` toggle, reporting a PASS/FAIL/INFO table
  with one remediation line per FAIL. `apply` re-runs `check` then points at the
  resolution for each finding. Every prerequisite is a `PATH` binary or the
  native toggle, so `apply` is guidance-only with no write path — it never
  installs packages and never modifies the repository (including `.editorconfig`
  / `.shellcheckrc`), user settings, or the plugin cache.

## [0.4.1]

### Changed

- Refresh of the bundled shared hook-utils library, which gains the git argv-grammar parser used by
  the guardrails plugin's git guards. No behavioral change to this plugin's hooks.

## [0.4.0]

### Changed

- **Missing prerequisites now skip visibly** (prerequisite-visibility wave;
  doctrine: a silently skipped feature is a defect). ShellCheck absent → the
  lint pass skips with a once-per-session notice to both Claude
  (`additionalContext`) and the user (`systemMessage`). shfmt absent while an
  `.editorconfig` opts the repo into formatting → same visible skip for the
  format pass (no opt-in stays quiet — the repo chose not to format). `jq`
  absent → the whole hook skips visibly. Findings and a pending notice compose
  into a single JSON document. Notice dedup state lives under
  `${CLAUDE_PLUGIN_DATA}/skip-notices`.
- Shared `hook-utils.sh` resynced with the new prerequisite-visibility helpers
  (jq-free notice emitters, once-per-session gate, jq gate).
- README now declares the full hook runtime: Bash (Git Bash on native Windows),
  `jq`, ShellCheck, and shfmt, each with its absence behavior.

## [0.3.0]

### Changed

- **Kill switch migrated to native `userConfig`.** The bash-format toggle is now the
  `bash_format_enabled` option (default `true`), read by the hook through the native
  `CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED` hook-process mirror. Configure interactively with
  `/plugin configure bash-format` or headless via `claude plugin install --config KEY=VALUE`.
- **BREAKING:** the `HOOK_BASH_FORMAT_ENABLED` environment variable is retired and no
  longer read. A consumer that set it in a settings `env` block must re-express the
  value as the matching `userConfig` option. Zero-config behavior
  is unchanged (hook on, same defaults). The `HOOK_TELEMETRY_SINK` telemetry seam is
  unaffected.

## [0.2.0]

### Changed

- **Breaking:** renamed the plugin `bash-lint` → `bash-format`, aligning with the hook-plugin
  `<tool>-format` verb family (`biome-format`, `ruff-format`, `powershell-format`) — the hook
  mutates files via shfmt, which "lint" undersold. This is a hard break with no marketplace
  `renames` entry: uninstall `bash-lint` and run `/plugin install bash-format@<marketplace>`.
  Renamed with it: the hook script (`hooks/bash-format.sh`), the telemetry `hook` value
  (`bash-lint` → `bash-format`), and the kill switch (`HOOK_BASH_LINT_ENABLED` →
  `HOOK_BASH_FORMAT_ENABLED` — re-set any disable override under the new name).
