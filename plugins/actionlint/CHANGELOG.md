# Changelog

All notable changes to the `actionlint` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.8.21]

### Changed

- **Instruction-surface de-slop (#2891, actionlint cluster).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change. The generated options block is ignore-fenced because
  `scripts/sync-plugin-options-docs.py` still emits em dashes from its shared template.

## [0.8.20]

### Fixed

- **Vendored `hook-utils.sh` skip latch (#3128).** The shared notice latch now
  keys on session and agent (a subagent gets its own first notice), stores a
  skip count in the marker (independent of `HOOK_TELEMETRY_SINK`), and emits a
  one-line re-notice every 8 skips instead of going silent after the first.
  The first `PATH probed:` dump omits other plugins' bin dirs. Copies stay
  byte-identical via `scripts/sync-hook-utils.sh`.

## [0.8.19]

### Changed

- **setup:** normalized restated setup-contract prose (preamble, probe-ladder
  opening, never-writes boundary, and/or headless-reconfigure recipe as present) to the
  canonical fleet wording, keeping the operable text inline with a provenance-only citation
  (whole-repo extract-ssot batch, #2698).
- **README:** deduplicated the hand-written option-scoping preamble against the
  generated options block, which already states both facts (#2698).

## [0.8.18]

### Fixed

- **`setup` skill:** the headless reconfiguration route no longer prescribes `claude plugin
  uninstall` + reinstall. That instruction rested on an unversioned claim that `claude plugin
  install --config` is ignored once a plugin is installed, and following it dropped the plugin's
  whole stored `pluginConfigs` entry, resetting every declared option to its manifest default.
  On Claude Code 2.1.240 a plain `claude plugin install … --config` against an already-installed
  plugin prints `already installed` and still writes the value, so that is now the documented
  route — stamped with the CLI version it was verified against
  ([#3111](https://github.com/melodic-software/claude-code-plugins/issues/3111)). `apply` also
  now separates the write from its effect: the stored value changes immediately, but the running
  session's hooks keep the `CLAUDE_PLUGIN_OPTION_*` they were handed at session start, so
  verification means rerunning `check` in a FRESH session — a same-session rerun reports the old
  value, which is not a failed write. It never asserts an unobserved change.
- **Docs:** the generated options block's headless route no longer implies `--config` applies
  only at install time, and now carries the CLI version its claim was verified against
  ([#3111](https://github.com/melodic-software/claude-code-plugins/issues/3111)). The block also
  now separates the write from its effect: the value is stored immediately, but hooks are handed
  their `CLAUDE_PLUGIN_OPTION_*` at session start, so a check run in the same session still
  reports the old value and that is not a failed write. Two upstream links that pointed at empty
  backward-compatibility anchors on the settings page were repointed at the headings that hold
  the content.

### Added

- **`setup` evals:** the skill now ships `evals/evals.json`, covering trigger and routing, the
  happy path, the guardrails it must not cross, and the corrected headless reconfiguration
  guidance ([#3111](https://github.com/melodic-software/claude-code-plugins/issues/3111)).

## [0.8.17]

### Changed

- **Fixture-building tests clear inherited git environment (#2872).** Suites
  that build a git fixture now unset `GIT_DIR`, `GIT_WORK_TREE`, and
  `GIT_CONFIG` so an inherited environment cannot write the fixture identity
  into the caller's repository. Test-only; no plugin behavior change.

## [0.8.16]

### Changed

- Sync `hook-utils.sh` from `lib/` — two header-echo comments removed in
  `hook::emit_telemetry` (comment-only; no behavior change).

## [0.8.15]

### Changed

- Behavior-preserving simplifications from the repository-wide batch-simplify pass:
  duplicated helpers folded, dead code and redundant constructs removed, no functional
  change. Every group was verified by a fresh-context verifier agent against the
  plugin's own test suite.

## [0.8.14]

### Fixed

- **Accurate PATH-miss notices with probe latch wording + `PATH probed:` diagnostic (#2732).** Skip is for this edit (probe re-runs; only the notice latches). Names
  Claude Code environment inheritance vs profile PATH; does not probe nvm layouts.

## [0.8.13]

### Changed

- **Docs:** actionable `/plugin configure` guidance now uses the marketplace-qualified form
  (`<plugin>@<marketplace>`; generated option blocks use `@<marketplace>`) per
  [`docs/extensibility-contract-smoke-tests.md`](../../docs/extensibility-contract-smoke-tests.md)
  Test E (#1360). Targetless references to the flow stay unqualified.

## [0.8.12]

### Fixed

- **hook-utils:** distinguish unresolved `physical_path`/`repo_root` answers and honor unquoted `#` in `bash_parse_segments` (#1487).

## [0.8.11]

### Fixed

- **hook-utils:** scope `read_file_path` to git worktrees when project dir unset (#1091).

## [0.8.10]

### Changed

- **Synced `hook-utils.sh`:** write `emit_telemetry`'s `data` payload to a temp file instead of passing it via `--argjson`, so payloads above the Windows command-line cap are not dropped (#1595).

## [0.8.9]

### Changed

- **Synced `hook-utils.sh`:** peel sudo clustered short options for chdir resolution (#1811); widen the valueless-short peel set and keep `-h` value-taking.

## [0.8.8]

### Changed

- **Synced `hook-utils.sh`:** peel sudo clustered short options for chdir resolution (#1811).

## [0.8.7]

### Changed

- **Synced `hook-utils.sh`:** refuse sub-minimum `stdin_read_timeout` values (#1883).

## [0.8.6]

### Changed

- **Synced `hook-utils.sh`:** `hook::jq_fields` returns 2 when jq is present but cannot parse the payload (#2157).

## [0.8.5]

### Changed

- **Shared `hook-utils.sh`: the jq gate now has a fail-CLOSED sibling, and the posture reasoning
  lives at the helper (#2146).** `hook::require_jq` is unchanged and still fails OPEN — one visible
  skip notice per session, then exit 0 — which is the correct posture for every hook in this plugin,
  so **nothing in this plugin's behaviour changes**. What is new is `hook::require_jq_blocking`, a
  second named function that denies the tool call instead, for the narrow class of guards whose job
  is blocking an irreversible operation (today only two, both in `guardrails`). A sibling function
  rather than a parameter, because a flag's omitted value would default to fail-open and a guard
  whose flag someone forgot would then fail open *silently* — the exact defect #2146 reports,
  reintroduced at the API. The two postures are now argued together in one block above both
  functions, which is what #2146 asked for: previously each call site asserted a posture in a
  comment and nothing where the decision is made explained it. Synced from `lib/hook-utils.sh`.

## [0.8.4]

### Changed

- **Carries the shared hook library's new `hook::is_enabled` predicate.** `hook::check_enabled`
  exits the process when a plugin is gated off, which is correct for a hook but wrong for a
  caller that must keep running afterward. The resolution is now also available as a predicate
  that returns instead of exiting. No behaviour of this plugin changes; the version moves so
  consumers receive the updated library.

## [0.8.3]

### Fixed

- **Shared `hook-utils.sh`: `hook::jq_fields` now REPORTS a NUL byte in a payload value
  (#2122).** 0.8.1 stopped a NUL from failing the helper's cardinality check, by stripping every
  NUL out of each value. That keeps the helper working, but stripping also silently rewrites the
  value — `--no-verify<NUL>x` arrives as `--no-verifyx` — so a caller that owns a block/allow
  verdict cannot tell a clean payload from one that carried a NUL, and matches against a token the
  payload never held contiguously. The fact is now reported in a new `HOOK_JQ_FIELDS_NUL` global,
  set on EVERY call including every failure path, so such a caller can fail closed on its own terms.
  It is computed from the values as the payload carried them, BEFORE the strip; strip first and the
  flag would read "0" on every payload. Values themselves are unchanged — still stripped, so a
  scanning caller still sees everything after the NUL. This plugin's own hooks do not consult the
  new global, so their behaviour is unchanged. Synced from `lib/hook-utils.sh`.

## [0.8.2]

### Fixed

- **Shared `hook-utils.sh`: `env -S` / `--split-string` no longer hides a whole command from the
  git guards (#2124).** `-S` exists so a shebang line can pass OPTIONS to env
  (`#!/usr/bin/env -S -i prog`), so the words it splits out are env's own arguments. The resolver
  spliced them back into the scan but resumed at the COMMAND dispatcher, which read a leading
  option in the split string as the command NAME and gave up — `env -S '-C <dir> git push --force'`
  resolved to no git at all, so every guard built on `hook::git_resolve_index` skipped the command
  unexamined. Parsing now resumes inside env's own option loop. That also keeps env's single chdir
  slot last-wins across the splice, so `env -C a -S '-C b git …'` reports `b`, matching GNU env.
  Synced from `lib/hook-utils.sh`.

## [0.8.1]

### Fixed

- **Shared `hook-utils.sh`: a NUL byte inside a payload value no longer makes `hook::jq_fields`
  come back empty (#2120).** The helper delimits its batched fields with NUL, and a JSON string may
  legitimately encode one — a `Write`/`Edit`/`NotebookEdit` content field can. jq emitted the raw
  byte, the read split that value in two, the cardinality check saw one value too many, and the
  helper returned non-zero — which every caller treats as "skip", so the hook exited without doing
  its work. Each value is now NUL-stripped INSIDE the jq filter, so the delimiter provably cannot
  occur in a value. Stripping is not a lesser alternative to an encoding scheme, it is the only
  representable behavior: a bash variable cannot hold a NUL byte, and the per-field command
  substitution this helper replaced dropped the byte and kept the rest of the value — so content
  AFTER a NUL is returned and scanned exactly as it was before the batching. Synced from
  `lib/hook-utils.sh`.

## [0.8.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.7.8]

### Changed

- **Shared `hook-utils.sh`: a hook invocation spawns three fewer external processes (#1978).**
  Every hook that buffers its stdin paid an `awk` (one float division, to slice the read timeout), a
  `printf | tr -d '\r'` pipeline (a fork and an exec to delete one byte class from a string bash
  rewrites in place), and a `jq -e .` validity probe over a buffer the read loop had already parsed
  with jq. On Windows Git Bash, where process creation is `fork()` emulation, each spawn costs
  ~140 ms. Behavior is unchanged: the slice keeps the three-decimal form `read -t` is given, the
  buffer is CR-stripped as before, and the completeness verdict is reused only when jq itself
  produced it — so a host without jq still fails open exactly as it did. Also adds
  `hook::jq_fields`, which extracts several fields from one payload in a single jq process for
  hooks that read two or three of them. Synced from `lib/hook-utils.sh`.

## [0.7.7]

### Fixed

- **Shared `hook-utils.sh`: the OS temp tree is no longer treated as project content (#1769).**
  `hook::read_file_path` scoped a file to the project by prefix-matching `CLAUDE_PROJECT_DIR`, so a
  session whose project directory is the user's home admitted everything under the OS temp root —
  including Claude Code's own per-session scratchpad, which lives there. Hooks that lint, rewrite, or
  autocorrect then ran on throwaway files that are not project content and carry no project config to
  opt out with; the reported case was `typos-format` autocorrecting a shell variable in a scratch
  script and silently breaking it. The guard now rejects a file inside the OS temp tree when the
  project root is outside it. The exemption is deliberate and load-bearing: when the project root
  itself lives under temp — a `mktemp -d` fixture checkout, which is how this repository's own hook
  suites run — its files are still accepted. Temp roots come from `TMPDIR` / `TMP` / `TEMP` plus the
  POSIX defaults, canonicalized through the same pipeline the membership comparison already uses.
  Synced from `lib/hook-utils.sh`.

## [0.7.6]

### Fixed

- **Shared `hook-utils.sh`: a wrapper's working-directory change is no longer lost when a caller
  parses only git's own global options (#1503).** `hook::git_resolve_index` walks wrapper programs
  (`env`, `sudo`, …) to reach the real `git` token, and a caller that scopes its git-global parsing
  to the slice starting at that token cannot see a relocation the wrapper already performed — GNU env
  documents `-C, --chdir=DIR` as "change working directory to DIR". The resolver now reports those
  directories in a new `HOOK_GIT_RESOLVED_WRAPPER_DIRS` result global, in execution order, so a
  caller composes them ahead of git's own globals instead of dropping them. Five spellings are read
  (`-C DIR`, `-CDIR`, `--chdir DIR`, `--chdir=DIR`, and a clustered `-vC DIR`), a repeat within one
  `env` is last-wins as env itself resolves it, and sudo's `-D`/`--chdir` is read in its unclustered
  spellings. A chdir spelled inside `-S`/`--split-string` is NOT read; that path already fails open
  for any command on `main` and is tracked in #1814. This plugin does not consume the new global; the sync keeps its copy
  byte-identical with the source. Synced from `lib/hook-utils.sh`.

## [0.7.5]

### Fixed

- **Shared `hook-utils.sh`: an in-project file spelled as a Windows 8.3 short name is no longer
  silently skipped by the shared membership guard (#1636).** `hook::physical_path` canonicalized
  with GNU realpath, which under Git Bash resolves symlinks but leaves 8.3 short names
  (`KYLESE~1`) unexpanded, so a short-form `file_path` failed the `CLAUDE_PROJECT_DIR` prefix
  comparison in `hook::read_file_path`. The lib now expands short names on Windows/MSYS hosts
  (new `hook::expand_8dot3`, via `cygpath -l`) before the comparison, and only when the expanded
  form actually differs; a genuinely out-of-project file is still skipped. This plugin's own
  hook met this exact defect first and has parsed `file_path` itself since 0.6.0 (#1133), so its
  behavior is unchanged — the sync fixes the shared guard that 0.6.0 deliberately left untouched
  for consumers that need it. Synced from `lib/hook-utils.sh`.

## [0.7.4]

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

### Changed

- **`stdin_read_timeout` is documented as the idle bound it now is.** This plugin already exposed
  the option, and its README, manifest description, and setup skill all described it as bounding
  "reading the hook payload from stdin before failing open" — a total read deadline. It is now an
  inactivity deadline: any byte resets it, so a producer that keeps emitting is bounded by Claude
  Code's own hook timeout rather than by this value, and the bound is read in four slices so a stall
  is detected within a quarter of the configured interval — except on a shell without fractional
  `read -t` (Bash 3.2, the macOS system shell), where the bound is read as one window and the
  detection can take up to two intervals. Documentation only — the configuration
  contract users read was materially misleading after the shared-library change above.

## [0.7.3]

### Changed

- **Test scaffolding: migrated `mktemp -p` temp file/dir creation to the portable `mktemp "$DIR/template"` form.** BSD/macOS `mktemp` has no `-p` flag; the directory now rides in the positional TEMPLATE argument instead, which both GNU and BSD `mktemp` accept identically. Test-only — no hook behavior change. Part of #1527 (`actionlint-check.test.sh`).

## [0.7.2]

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

## [0.7.1]

### Fixed

- **Headless reconfigure recipe now preserves install scope (#1406).** The `claude plugin
  uninstall` → `claude plugin install ... --config` recipe in `skills/setup/SKILL.md` defaulted
  both halves to `-s user`. When this plugin is installed at `project` or `local` scope, that
  silently uninstalled a separate user-scope record while the effective project/local install kept
  loading, and the reinstall landed at a scope that does not load. Both commands now carry
  `-s <scope>`, sourced from what `claude plugin list` reports for this plugin — the same fix
  already applied to `session-flow` and `rate-limit-guard` in #1393.
  The recipe also now requires the reinstall to re-supply **every** key whose value should
  stay non-default, not only the key being changed: uninstalling drops the stored
  `pluginConfigs` entry, so an omitted key silently falls back to its manifest default.
  Record the current values before uninstalling.

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
