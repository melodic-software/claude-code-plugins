# Changelog

All notable changes to the `bash-format` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.5.3]

### Changed

- Sync of the shared `hook-utils.sh`: the git-option parser now distinguishes
  `--config-env` (an env-var name) from `-c`/`--config` (an inline value) and adds the
  `hook::git_effective_config_values` resolver — hardened so every `--config-env` name git
  reads (non-identifier, leading-dash, ambient or command-line) resolves, the last value
  for a key wins, and a `!` shell alias inherits the enclosing git environment (`#740`).
  No behavior change for this plugin — it does not read git config values; shipped so
  consumers receive the shared library update.

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
