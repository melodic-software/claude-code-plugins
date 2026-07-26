# Changelog

All notable changes to the `markdown-format` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.8.2]

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

## [0.8.1]

### Fixed

- **The telemetry payload could be falsified rather than merely lost.**
  `build_data_json` handed the findings array to `jq -n` as an `--argjson`
  value. Windows caps a process command line at 32767 characters, and
  `data.findings` is deliberately uncapped, so the array blew past that
  somewhere between 300 and 600 entries (reproduced with the hooks' own jq:
  300 pass, 600 fail with `rc=126`, "argument list too long"). `jq` never ran
  and the fallback emitted an envelope claiming **zero** findings, with `tool`
  and `file` blanked — for the noisiest files in the repository, which are the
  ones a sink is most likely wired for. Telemetry is documented best-effort and
  lossy, so a *dropped* envelope is inside contract; one that *arrives*
  reporting a 600-finding file as clean is not. The array now reaches `jq` on
  stdin; `tool` and `file` stay as arguments, both bounded by a path length.
  The shared `hook::emit_telemetry` hands the finished payload over the same
  way (#1595), so an oversized envelope is currently dropped rather than
  delivered — the correct failure direction, and the one this change
  establishes. The 600-finding case asserts the invariant that holds either way
  and keeps holding once #1595 lands: lost, never falsified.
- **Carriage returns leaked into the report.** `markdownlint-cli2` is a Node
  process whose stdout is CRLF-terminated on Windows, and command substitution
  strips only the trailing newline — so every retained violation line carried a
  CR that survived JSON-escaping into `additionalContext` as a literal `\r`.
- **The digest-store prune ran on every Markdown edit and was unbounded in
  depth.** It now runs only when a *new* digest file is created — the steady
  state for a repeatedly-edited file already has one, so the common path no
  longer walks the directory at all — and carries `-maxdepth 1`.
  `CLAUDE_PLUGIN_DATA` is shared with the `trust-approvals` tree and with
  whatever a future version of this plugin puts there; a recursive age-based
  `-delete` has no business reaching into a sibling's state.
- **The rule histogram truncated silently.** It named the top five rules and
  stopped, so `MD013 x48` read as the whole story on a file where twelve more
  rules were firing. It now carries `+N more rule(s)`, the same way the finding
  list already reported its own remainder. A test asserts the suffix is absent
  when every rule fits, so it cannot become permanent decoration.

## [0.8.0]

### Fixed

- **Lint reporting is bounded instead of unbounded.** The hook appended every
  line of markdownlint's whole-file output to `additionalContext` on every
  touch — no cap, no baseline, no dedup — so a file edited repeatedly produced
  a full re-dump each time. Measured in one consuming session: 21 dumps,
  ~378 KB (~95K tokens), one file dumped eight times with byte-identical
  content, and 97% of one real file's 324 findings from a single rule that
  repository intentionally violates. Now every run reports the finding count
  and a rule histogram (which rules dominate, highest first), lists at most 20
  individual violations, and reports the omitted remainder as a count.
  markdownlint's own banner lines (its version, the resolved `Finding:` glob
  list, `Linting:`, `Summary:`) no longer enter the report at all — they say
  nothing about the edited file and cost context on every edit.
- **An unchanged finding set no longer repeats its detail.** The finding set is
  content-hashed per file per session under `CLAUDE_PLUGIN_DATA`; a repeat with
  the same set reports its summary and omits the per-finding lines. The
  **summary always goes out** — suppressing the message entirely would
  reproduce, on this plugin, exactly the invisible-hook defect the disclosure
  below fixes.
- **A run that rewrote the file is no longer silent about it.** On the
  clean-after-fix path the hook emitted nothing at all, so `--fix` rewriting the
  user's file was indistinguishable from the hook not running. The count
  markdownlint-cli2 reports (`Attempted: N fixes in 1 file`) is now surfaced on
  both channels. It is only a count: `markdownlint-cli2` offers no per-fix
  detail, so neither can this hook.

### Added

- **`markdown_format_max_findings` userConfig (default `20`, `0` = unlimited).**
  Bounds the per-run violation listing only; the count and rule histogram are
  always reported. Read from the
  `CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_MAX_FINDINGS` environment mirror, because
  shell-form hook commands reject `${user_config.*}` substitution outright. A
  value that is not a non-negative integer falls back to the default and is
  never interpolated anywhere.
- Contract tests for the cap, the configurable cap (including a garbage value),
  the rule histogram, banner exclusion, the delta gate in both directions,
  uncapped telemetry, and the applied-fix disclosure.

### Changed

- The telemetry payload is deliberately **not** capped — a sink is a machine,
  and the cap exists to protect the model's context, not a log file.
  `data.findings` keeps its shape and its full contents.

## [0.7.1]

### Changed

- **Test scaffolding: migrated `mktemp -p` temp file/dir creation to the portable `mktemp "$DIR/template"` form.** BSD/macOS `mktemp` has no `-p` flag; the directory now rides in the positional TEMPLATE argument instead, which both GNU and BSD `mktemp` accept identically. Test-only — no hook behavior change. Part of #1527 (`markdown-format.test.sh`).

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
  The approval signature is content-addressed over the configuration AND every
  repository file its string literals — plus, since a YAML plain scalar carries
  no quotes, its path-shaped bare tokens — resolve to, through Node's CommonJS
  resolution candidates (`.cjs`/`.mjs`/`.js`/`.json`/`.node` extensions and
  directory `package.json`/`index.*` entry points), transitively, bounded — so a
  change to the configuration or to a referenced repository module — e.g. a
  branch switch swapping rule-module bytes under an unchanged config — revokes
  the approval; the gate fails closed when `CLAUDE_PLUGIN_DATA` is unavailable
  or the module scan overflows its bound. A reference that RESOLVES outside the
  repository — a symlink aimed out of the tree, or a `../` escape — refuses
  approval rather than being skipped: no signature over repository content can
  cover it, so re-aiming the symlink at a different existing external target
  would otherwise leave the approval valid while Node follows the new one. On a
  host with no canonicalizer the resolution degrades to the lexical path, which
  would read an escaping symlink as in-repository; a symlink whose physical path
  came back unchanged is the signature of that degradation and refuses approval
  too — the same fail-closed answer the membership scope already gives. Module-key detection in declarative
  configs is a fail-closed textual over-approximation rather than a second
  parser (which would only open a differential-parsing gap against
  markdownlint-cli2's own parser): the literal key words anywhere in the file
  gate as code-loading, and constructs able to synthesize a hidden spelling
  (JSONC `\uXXXX` escapes; YAML `\x`/`\u`/`\U` escapes, escaped line joins,
  `!!` tags) mark the configuration unverifiable — gated with no approval
  route, since text whose meaning cannot be read cannot be reviewed. Those two
  tiers are independent tests rather than a chain, so a config carrying a literal
  key AND an escaped module value still reaches the escape verdict instead of
  having it suppressed by the key match.

  **An executable (`.cjs`/`.mjs`) config that declares one of the module-loading
  keys now gets no approval route at all** — a deliberate narrowing.
  markdownlint-cli2 resolves those entries itself, so an entry may be any
  expression producing a string (`path.join(...)`,
  `["./rules","x.cjs"].join("/")`, a concatenation, a helper call, a value
  imported from elsewhere), and no text scan can enumerate that space. A repo
  that names custom rules from a JS config must move those entries to a
  declarative config, where they are data this scan reads exactly rather than an
  expression it would have to predict; an executable config that declares none of
  those keys stays approvable as before. A module specifier the scan cannot pin to
  a file likewise refuses approval, because a
  signature that omits the module would keep honoring an approval across
  arbitrary edits to it: any path-building machinery in a JS source
  (an import of the `path` module — refused at the import, because a call site
  can be spelled through any alias while the import cannot; `require.resolve`,
  `import.meta`, `__dirname`/`__filename`, `process.*`, template
  interpolation, string concatenation), a
  loader whose argument is not a plain quoted specifier, and a string literal
  carrying a letter-capable escape sequence (which Node decodes to a different
  path than the raw text). Detection is file-wide rather than anchored on a
  loader call: markdownlint-cli2 resolves `customRules` entries itself, so
  `customRules: [path.join(__dirname, "rules", "x.cjs")]` — or
  `[process.env.RULE]` — carries no loader token at all, and JavaScript permits
  a comment or newline at any token boundary, so `require/*c*/(…)` sits outside
  any fixed window. The loader test deletes every plainly-written call first and
  then looks for a loader token in the residue, which needs no window. Every
  pattern is POSIX ERE — no `\b`, whose GNU-only meaning would turn the whole
  predicate into a silent pass under the macOS system grep this hook supports.
  Previously the hook warned once and executed anyway, so a malicious
  repository's checked-in config could run arbitrary code on a routine
  markdown edit. Declarative rule-only configuration is unaffected. The edit
  itself is still never blocked — the hook always exits 0.

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

## [0.6.5]

### Fixed

- C1 fd1-leak detector in the hook contract test: the differential threshold
  introduced in `0.6.2` (ported from `desktop-notification` `#751`) carried the same
  latent defect — `THRESHOLD_MS` was derived as `SINK_SLEEP * 1000 / 2`, so widening
  `SINK_SLEEP` widened the threshold proportionally and left the margin unchanged by
  construction (`#448`, reopened after reproducing on clean `main`: delta=3697ms
  false-fail with no leak present, in the `desktop-notification` copy this test was
  ported from). `THRESHOLD_MS` now asserts the real invariant directly —
  sink-sleep-minus-a-safety-margin, not half the sleep — and `SINK_SLEEP` widens from
  6s to 8s (still under the 10s ceiling documented against EXIT-cleanup file-locking
  on Windows) for more absolute separation between ambient noise and the leak signal.
  The safety margin is sized so BOTH sides of the threshold clear the 2150ms of worst
  observed no-leak noise, not just the noise side: a threshold too close to the leak
  signal lets a load shift that inflates every baseline sample and then subsides
  before the slow run subtract real leak signal out of the delta, and the detector
  reports no leak. At `SINK_SLEEP`=8s and a 3000ms margin the threshold sits at
  5000ms — 2850ms of noise-side margin, 3000ms of leak-side margin.
  No behavior change for this plugin — the hook is untouched; test-only.

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
