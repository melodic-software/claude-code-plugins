# Changelog

All notable changes to the `markdown-format` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.6.4]

### Fixed

- **Headless reconfigure recipe now preserves install scope (#1406).** The `claude plugin
  uninstall` → `claude plugin install ... --config` recipe in `skills/setup/SKILL.md` defaulted
  both halves to `-s user`. When this plugin is installed at `project` or `local` scope, that
  silently uninstalled a separate user-scope record while the effective project/local install kept
  loading, and the reinstall landed at a scope that does not load. Both commands now carry
  `-s <scope>`, sourced from what `claude plugin list` reports for this plugin — the same fix
  already applied to `session-flow` and `rate-limit-guard` in #1393.

## [0.6.3]

### Fixed

- **Out-of-tree Markdown is no longer linted when `CLAUDE_PROJECT_DIR` is
  unset.** In an autonomous session whose working directory is not a repository,
  `CLAUDE_PROJECT_DIR` is unset and the hook previously linted the `.md`
  wherever it lived — including a lane's temporary comment-body composed outside
  any repository (e.g. for `gh issue comment --body-file`), firing repo-doc rules
  (MD041, MD013) that do not apply to it. The hook now falls back to
  git-working-tree membership when `CLAUDE_PROJECT_DIR` is unset: a file under no
  git working tree is skipped, while a repository file edited in such a session
  is still linted. Membership is decided on the physical path (symlinks
  resolved), matching the set-`CLAUDE_PROJECT_DIR` guard, so an in-repository
  symlink to an out-of-tree file cannot pull the external target into `--fix`.
  Where no canonicalizer is available the membership test fails closed: a
  symlink whose physical path could not be resolved is skipped rather than
  admitted on its lexical parent. The membership probe also clears Git's
  repository-selection and discovery environment variables, so an inherited
  `GIT_DIR`/`GIT_WORK_TREE` cannot answer for a directory that is not in a
  working tree. Behavior when `CLAUDE_PROJECT_DIR` is set is unchanged.

## [0.6.2]

### Changed

- Test-only: the C1 fd1-inheritance-leak detector in the hook contract test now measures the
  slow-sink cost *differentially* — a baseline (fast sink, min of several runs) subtracted from
  the slow-sink run — instead of asserting a fixed 2000ms wall-clock bound. The fixed bound sat
  inside the machine- and load-dependent spawn-overhead band (already ~1.5s per hook on Windows
  Git Bash, higher under parallel suites) and would false-fail with no leak present. No behavior
  change for this plugin — the hook is untouched; shipped so the test stays reliable under load.

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
  Markdown...") now shows while the hook runs. Config-only — no runtime behavior
  change.

## [0.5.4]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.5.3]

### Changed

- Documentation-only prose hygiene: reworded changelog entries and hook comments
  to describe past changes in consumer-meaningful terms, dropping
  maintainer-internal vocabulary and a cross-plugin reference. No behavior
  change to the hook or its output.

## [0.5.2]

### Changed

- Hook stdin is read via the shared `hook::buffer_stdin` helper (bounded `read -t`,
  default 2s) instead of a bare `cat`, so a Windows Win32-pipe late-EOF stall can no
  longer hang the hook indefinitely. Empty or timed-out stdin exits as a skip, matching
  the existing empty-payload behavior.

## [0.5.1]

### Changed

- Setup `check` downgrades every prerequisite absence from FAIL to INFO while
  the plugin's toggle is disabled (the hook exits through its enabled-gate
  before probing, so a deliberately disabled plugin is not broken).

## [0.5.0]

### Added

- **`setup` skill on the uniform contract.** `check` verifies the hook's runtime
  prerequisites read-only (Bash, `jq`, `markdownlint-cli2` resolution,
  discovered markdownlint config + trust boundary, effective toggle);
  `apply` re-checks and resolves — guidance for system tools and the native
  toggle, and an explicitly requested `apply install-lint` as its only write
  path: `markdownlint-cli2` added as a dev dependency via the repository's own
  package manager (npm, pnpm, Yarn, or Bun, resolved from the repo's lockfile
  and `packageManager` field).
  Non-interactive when the action argument is supplied.

## [0.4.1]

### Changed

- Refresh of the bundled shared hook-utils library, which gains a git argv-grammar parser used by
  git-guard hooks. No behavioral change to this plugin's hooks.

## [0.4.0]

### Changed

- **Missing-prerequisite notices now reach the user too, once per session.**
  The jq and markdownlint-cli2 absence
  warnings — previously an `additionalContext`-only message repeated on every
  edit — now use the shared visible-skip mechanism: one notice per session on
  both channels (`additionalContext` for Claude, `systemMessage` for the
  user). Notice dedup state lives under `${CLAUDE_PLUGIN_DATA}/skip-notices`.
- Shared `hook-utils.sh` resynced with the new prerequisite-visibility helpers
  (jq-free notice emitters, once-per-session gate, jq gate).

## [0.3.0]

### Changed

- **Kill switch migrated to native `userConfig`.** The toggle is now the
  `markdown_format_enabled` boolean (default `true`), read by the hook through the
  native `CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED` hook-process mirror. Configure
  interactively with `/plugin configure markdown-format` or headless via
  `claude plugin install --config KEY=VALUE`.

### Breaking

- The `HOOK_MARKDOWN_FORMAT_ENABLED` environment variable is retired and no longer
  read. A consumer that set it in a settings `env` block must
  re-express the value as the matching `userConfig` option. Zero-config behavior is
  unchanged (hook on, same defaults). The `HOOK_TELEMETRY_SINK` telemetry seam is unaffected.

## [0.2.0]

### Changed

- **Breaking:** renamed the plugin `markdown-formatter` → `markdown-format`, aligning with the
  hook-plugin `<tool>-format` verb family (`biome-format`, `ruff-format`, `powershell-format`).
  This is a hard break with no marketplace `renames` entry: uninstall `markdown-formatter` and
  run `/plugin install markdown-format@<marketplace>`. Skills, hook behavior, telemetry `hook`
  value (`markdown-format`), and the `HOOK_MARKDOWN_FORMAT_ENABLED` kill switch are unchanged.
