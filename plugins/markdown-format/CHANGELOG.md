# Changelog

All notable changes to the `markdown-format` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.7.0]

### Security

- **Code-loading markdownlint configuration is now gated on explicit approval.**
  When the discovered configuration can execute repository-supplied code
  (`.cjs`/`.mjs` config files, or `customRules`/`markdownItPlugins`/
  `outputFormatters` module identifiers), the hook no longer runs
  `markdownlint-cli2` after a one-time non-blocking advisory — it skips the
  lint run, with a visible once-per-session notice on both channels, until the
  user approves that exact configuration-content state by creating the marker
  directory named in the notice (under `${CLAUDE_PLUGIN_DATA}/trust-approvals`).
  Any configuration change revokes the approval; the gate fails closed when
  `CLAUDE_PLUGIN_DATA` is unavailable. Previously the hook warned once and
  executed anyway, so a malicious repository's checked-in config could run
  arbitrary code on a routine markdown edit. Declarative rule-only
  configuration is unaffected. The edit itself is still never blocked — the
  hook always exits 0.

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
