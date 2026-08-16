# Changelog

All notable changes to the `bash-format` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.7.16]

### Fixed

- **Accurate PATH-miss notices with probe latch wording + `PATH probed:` diagnostic (#2732).** Skip is for this edit (probe re-runs; only the notice latches). Names
  Claude Code environment inheritance vs profile PATH; does not probe nvm layouts.

## [0.7.15]

### Changed

- **Docs:** actionable `/plugin configure` guidance now uses the marketplace-qualified form
  (`<plugin>@<marketplace>`; generated option blocks use `@<marketplace>`) per
  [`docs/extensibility-contract-smoke-tests.md`](../../docs/extensibility-contract-smoke-tests.md)
  Test E (#1360). Targetless references to the flow stay unqualified.

## [0.7.14]

### Changed

- **Content-mutation disclosure contract tests (#1596).** The shfmt gate-on suite now
  asserts the `systemMessage` emitted when shfmt rewrites a file; hook comments document
  the conformance rationale.

## [0.7.13]

### Fixed

- **hook-utils:** distinguish unresolved `physical_path`/`repo_root` answers and honor unquoted `#` in `bash_parse_segments` (#1487).

## [0.7.12]

### Fixed

- **hook-utils:** scope `read_file_path` to git worktrees when project dir unset (#1091).

## [0.7.11]

### Changed

- **Synced `hook-utils.sh`:** write `emit_telemetry`'s `data` payload to a temp file instead of passing it via `--argjson`, so payloads above the Windows command-line cap are not dropped (#1595).

## [0.7.10]

### Changed

- **Synced `hook-utils.sh`:** peel sudo clustered short options for chdir resolution (#1811); widen the valueless-short peel set and keep `-h` value-taking.

## [0.7.9]

### Added

- Disclose shfmt rewrites on the user channel.

## [0.7.7]

### Changed

- **Synced `hook-utils.sh`:** refuse sub-minimum `stdin_read_timeout` values (#1883).

## [0.7.6]

### Changed

- **Synced `hook-utils.sh`:** `hook::jq_fields` returns 2 when jq is present but cannot parse the payload (#2157).

## [0.7.5]

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

## [0.7.4]

### Changed

- **Carries the shared hook library's new `hook::is_enabled` predicate.** `hook::check_enabled`
  exits the process when a plugin is gated off, which is correct for a hook but wrong for a
  caller that must keep running afterward. The resolution is now also available as a predicate
  that returns instead of exiting. No behaviour of this plugin changes; the version moves so
  consumers receive the updated library.

## [0.7.3]

### Fixed

- **Shared `hook-utils.sh`: `hook::jq_fields` now REPORTS a NUL byte in a payload value
  (#2122).** 0.7.1 stopped a NUL from failing the helper's cardinality check, by stripping every
  NUL out of each value. That keeps the helper working, but stripping also silently rewrites the
  value — `--no-verify<NUL>x` arrives as `--no-verifyx` — so a caller that owns a block/allow
  verdict cannot tell a clean payload from one that carried a NUL, and matches against a token the
  payload never held contiguously. The fact is now reported in a new `HOOK_JQ_FIELDS_NUL` global,
  set on EVERY call including every failure path, so such a caller can fail closed on its own terms.
  It is computed from the values as the payload carried them, BEFORE the strip; strip first and the
  flag would read "0" on every payload. Values themselves are unchanged — still stripped, so a
  scanning caller still sees everything after the NUL. This plugin's own hooks do not consult the
  new global, so their behaviour is unchanged. Synced from `lib/hook-utils.sh`.

## [0.7.2]

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

## [0.7.1]

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

## [0.7.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.6.12]

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

## [0.6.11]

### Fixed

- **Bare `[*]` is no longer a shell formatting opt-in (#1817).** `section_applies_to_shell`
  treated a catch-all `[*]` section as governing shell files, so any repo with a generic
  `.editorconfig` (typically only `end_of_line` / `insert_final_newline` under `[*]`) had its
  shell scripts rewritten to shfmt's built-in defaults. Opt-in now requires an explicit shell
  glob — `[*.sh]`, `[*.bash]`, `[*.{sh,bash}]`, or a path-prefixed form like `[**/*.sh]`.
  Path-only sections such as `[scripts/**]` remain excluded.

- **ShellCheck/shfmt path handling no longer surfaces `openBinaryFile` on Windows (#1817).**
  On Windows/MSYS the hook now prefers `cygpath -lm` (mixed long form) for tool invocations when
  that path exists, re-checks that the file is still present immediately before shfmt/ShellCheck
  run (closing a race with deleted scratch/worktree files), retries the original path spelling if
  ShellCheck still reports `openBinaryFile`, and strips any remaining `openBinaryFile` noise so it
  never becomes a findings line. `openBinaryFile: does not exist` is ShellCheck's (GHC's) missing-
  file error — valid path forms already lint cleanly; this hardens the intermittent miss case.

### Changed

- README and `/bash-format:setup` now document that a bare `[*]` is not a formatting opt-in;
  consumers who want shfmt must add an explicit shell glob section.

## [0.6.10]

### Fixed

- **A failed `shfmt --apply-ignore` run no longer re-formats the file without the flag (#1817).**
  The format pass was `shfmt --apply-ignore -w "$FILE" || shfmt -w "$FILE"`. The fallback exists for
  shfmt below 3.8, which rejects the flag and cannot honor direct-file `ignore` rules anyway — but
  `||` fires on *any* failure, so on a 3.8+ shfmt a run that failed for an unrelated reason silently
  re-formatted the file with the opt-out discarded, re-tabbing a script the repo's
  `.editorconfig` `[*.sh] ignore = true` had asked shfmt to leave alone. It presents as
  intermittent, because it only shows when the first call happens to fail.

  The version is now decided by **probing the flag** (`shfmt --apply-ignore --version`) rather than
  by inferring it from a failed format run, which is what confused "this shfmt has no such flag"
  with "this run failed". Where the flag exists, a failing run now leaves the file untouched — the
  only safe reading of a formatter that did not complete. Old shfmt still gets the plain in-place
  format it always did — but only on a **confirmed** unsupported-flag rejection (the flag parser's
  error naming `apply-ignore`); a probe that fails for any other reason (a wrapper flaking on its
  first invocation, a transient exec error) says nothing about the flag, so the file is left
  untouched and the skip is reported in the hook's notice rather than falling back to a mutation
  through the same discarded opt-out.

  Reproduced with a stub shfmt that answers the capability probe but fails the `-w` run: **before**,
  a file in an `ignore = true` repo is reformatted; **after**, it is byte-identical.

## [0.6.9]

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

## [0.6.8]

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
