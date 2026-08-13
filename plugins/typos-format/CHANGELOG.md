# Changelog

All notable changes to the `typos-format` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.6.15]

### Changed

- **Docs:** actionable `/plugin configure` guidance now uses the marketplace-qualified form
  (`<plugin>@<marketplace>`; generated option blocks use `@<marketplace>`) per
  [`docs/extensibility-contract-smoke-tests.md`](../../docs/extensibility-contract-smoke-tests.md)
  Test E (#1360). Targetless references to the flow stay unqualified.

## [0.6.14]

### Fixed

- **hook-utils:** distinguish unresolved `physical_path`/`repo_root` answers and honor unquoted `#` in `bash_parse_segments` (#1487).

## [0.6.13]

### Fixed

- **Bundled `default-typos.toml` parses again (#1257 follow-up):** `extend-ignore-re` was
  written as a TOML table (`[default.extend-ignore-re]` with the regex as a key), which
  typos-cli rejects — `invalid type: map, expected valid sequence` — so every hook run
  failed as a tool break instead of spell-checking. Now the documented array form under
  `[default]`, restoring both the spell-check and the SHA-corruption guard the file
  exists to carry.

## [0.6.12]

### Fixed

- **hook-utils:** scope `read_file_path` to git worktrees when project dir unset (#1091).

## [0.6.11]

### Changed

- **Synced `hook-utils.sh`:** write `emit_telemetry`'s `data` payload to a temp file instead of passing it via `--argjson`, so payloads above the Windows command-line cap are not dropped (#1595).

## [0.6.10]

### Changed

- **Synced `hook-utils.sh`:** peel sudo clustered short options for chdir resolution (#1811); widen the valueless-short peel set and keep `-h` value-taking.

## [0.6.9]

### Changed

- **Synced `hook-utils.sh`:** peel sudo clustered short options for chdir resolution (#1811).

## [0.6.8]

### Changed

- **Synced `hook-utils.sh`:** refuse sub-minimum `stdin_read_timeout` values (#1883).

## [0.6.7]

### Changed

- **Synced `hook-utils.sh`:** `hook::jq_fields` returns 2 when jq is present but cannot parse the payload (#2157).

## [0.6.6]

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

## [0.6.5]

### Changed

- **Carries the shared hook library's new `hook::is_enabled` predicate.** `hook::check_enabled`
  exits the process when a plugin is gated off, which is correct for a hook but wrong for a
  caller that must keep running afterward. The resolution is now also available as a predicate
  that returns instead of exiting. No behaviour of this plugin changes; the version moves so
  consumers receive the updated library.

## [0.6.4]

### Changed

- **Upstream doc stamps re-verified against the live pages (2026-08-10).** Each dated claim below was re-checked against the complete raw markdown source of the page it cites (`https://code.claude.com/docs/en/<page>.md`), not a summarized fetch, and each was confirmed by a verbatim quote before its stamp was refreshed. No claim changed; only the verification dates moved.

  - `hooks/typos-format.sh` — the same `${user_config.*}` shell-form rejection and
    `CLAUDE_PLUGIN_OPTION_<KEY>` export guarantee (plugins reference, "User configuration").

## [0.6.3]

### Fixed

- **Shared `hook-utils.sh`: `hook::jq_fields` now REPORTS a NUL byte in a payload value
  (#2122).** 0.6.1 stopped a NUL from failing the helper's cardinality check, by stripping every
  NUL out of each value. That keeps the helper working, but stripping also silently rewrites the
  value — `--no-verify<NUL>x` arrives as `--no-verifyx` — so a caller that owns a block/allow
  verdict cannot tell a clean payload from one that carried a NUL, and matches against a token the
  payload never held contiguously. The fact is now reported in a new `HOOK_JQ_FIELDS_NUL` global,
  set on EVERY call including every failure path, so such a caller can fail closed on its own terms.
  It is computed from the values as the payload carried them, BEFORE the strip; strip first and the
  flag would read "0" on every payload. Values themselves are unchanged — still stripped, so a
  scanning caller still sees everything after the NUL. This plugin's own hooks do not consult the
  new global, so their behaviour is unchanged. Synced from `lib/hook-utils.sh`.

## [0.6.2]

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

## [0.6.1]

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

## [0.6.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.5.3]

### Fixed

- **A residual finding that moved between the hook's two passes is no longer disclosed as a rewrite
  typos never made.** Classification keyed each residual by `line_num` + token, which assumes both
  passes saw the same file. They need not: Claude Code runs every matching `PostToolUse` hook in
  parallel, and `typos-format` and `markdown-format` both declare the matcher `"Write|Edit"`, so a
  sibling formatter can reflow the file between the scan and the write and carry an untouched
  finding to a different line. The moved residual then failed to match its own scan entry and was
  reported as an applied correction — a false mutation disclosure on the one channel this hook
  exists to make trustworthy. Residuals are now matched by token PAIRED WITH their correction
  decision and cancelled by COUNT, so a finding that merely moved still cancels its scan entry, and
  residual line numbers are taken from the write pass's own output rather than the scan's stale
  ones. The correction list is part of the key because one spelling can carry two decisions in one
  file — an occurrence reached by `extend-identifiers` beside one reached by `extend-words`, or a
  fixable occurrence beside a disallowed one. Keyed on the token alone those merge, and the count
  can then retire the fixable entry and disclose the disallowed one instead: a rewrite claimed at
  the wrong line with a blank correction, while the rewrite that really happened goes unmentioned.
  Which scan occurrences a cancellation consumes is chosen by line first: a scan finding sitting on
  a line the write pass reported as residual is cancelled ahead of one that is not, so when nothing
  moved the attribution is exact and only a real reflow falls back to dropping the earliest. Without
  that preference a token appearing three times with only the middle one residual reported the
  residual line as applied and dropped a rewrite that really happened. The count is the guarantee;
  the applied line numbers are best-effort for a repeated finding that genuinely moved. That
  preference is a linear partition over an object lookup rather than a sort over `index`, for the
  same reason the membership check beside it is an object: `index` is a linear scan, and one per
  entry over a cluster of repeats is quadratic — 10,000 repeats of one token measured 31s against
  the 15s handler budget, and 0.07s at the 500 the existing scale fixtures use, so a fixture that
  size cannot see it. Classification runs after the file is already rewritten, so blowing that
  budget is a silent mutation with no disclosure.
  The trade is deliberate and
  one-directional: counting can only UNDER-report an applied correction (a missing disclosure
  line), never invent one. Still unclosed, and stated in the source: a concurrent writer that
  DELETES a finding outright is attributed to typos, which needs file locking no hook-level
  primitive offers.

## [0.5.2]

### Changed

- **Wrapper coaching prose trimmed from the hook's injected reports (#2021, remediation line 3).**
  The hook-surface classification pass marked typos-format a hybrid whose wired surface is mostly
  injected wrapper prose around the report-only findings. The per-finding remediation tail ("if
  intentional, add it to extend-words…"), formerly repeated on every residual line, is replaced by
  one trailing pointer for the whole list; the applied-path disclosure keeps its facts (dictionary
  source, no-memory re-correction, allow-list route) at less than half the length; and the
  report-only header drops its option-explainer parenthetical. The finding lists themselves —
  residual findings with the tool's suggested corrections, and applied rewrites disclosed on both
  channels — are policy-class ground truth and are unchanged.

## [0.5.1]

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

## [0.5.0]

### Changed

- **Report-only is now the default; write mode is an explicit opt-in (#1809).** The
  `typos_format_write_changes` userConfig default flips `true` → `false` in both the manifest and
  the script fallback, so the out-of-the-box hook reports findings and never modifies a file. A
  dictionary autocorrect is a content mutation the user never asked for (#1257's silent SHA
  corruption is one instance), and an unconditional writer here raced the sibling
  `markdown-format` writer on every Markdown edit with no defined precedence — Claude Code runs
  matching `PostToolUse` hooks in parallel with no ordering primitive. Part of #1809's
  single-writer decision: by default at most one in-place rewriter matches any file class.
  Consumers who want corrections applied set the option to `true`, accepting last-writer-wins
  ordering with any sibling formatter hook that rewrites the same file (disclosed in the README;
  residual scoped-writer overlap is tracked fleet-wide in #875). The write gate now requires the
  literal `true` — the mutating direction is the one that needs the exact opt-in spelling, so a
  typo'd option value stays report-only. Zero-config reporting, disclosure of applied rewrites in
  write mode, and remediation guidance are unchanged.

## [0.4.4]

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

## [0.4.3]

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

## [0.4.2]

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

## [0.4.1]

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

## [0.4.0]

### Fixed

- **Every correction the hook applies is now disclosed on both channels.** On the
  all-fixed path the hook emitted nothing at all — no `additionalContext`, no
  `systemMessage`, telemetry only — so a rewrite drawn from typos' built-in
  dictionary reached the file with the only trace being the harness's generic
  "a PostToolUse hook modified this file" notice: no hook name, no word, no
  diff. An acronym or identifier the dictionary maps to an unrelated English
  word was therefore corrupted invisibly, indistinguishably from a benign
  reformat. The hook now reports each applied rewrite — token, replacement, and
  line — to Claude via `additionalContext` and to the user via `systemMessage`,
  capped at ten per run with a count of the remainder so the disclosure cannot
  itself become a context flood.
- **The allow-list remediation moved onto the applied-correction path.** The
  "if intentional, add it to `extend-words` / `extend-identifiers`" guidance sat
  only on the residual branch, so it never fired for the corrections that
  actually change file content — the one case where it is load-bearing. A
  dictionary autocorrect has no memory: a word repaired by hand is rewritten
  again on the next edit until the repo allow-lists it, and until now nothing
  said so.

### Added

- **`typos_format_write_changes` userConfig (default `true`).** Set it to
  `false` for a report-only hook: findings are reported and no file is
  modified. Read from the `CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_WRITE_CHANGES`
  environment mirror, because shell-form hook commands reject
  `${user_config.*}` substitution outright.
- **`data.applied` on the telemetry envelope** — the corrections this run wrote,
  as `{typo, correction, line}`. Additive; `data.findings` keeps its existing
  residual-only meaning and shape.
- **`/typos-format:setup check` reports the effective write mode.** The setup
  skill described a single tunable and probed only `typos_format_enabled`, so
  with `typos_format_write_changes=false` it could report the hook fully
  operational to a user who invoked it precisely because spell-fixing was not
  happening. Write mode is now a reported INFO row with its own remediation —
  including the alternative that usually fits better, allow-listing the specific
  words rather than turning every correction off.
- **Stub-driven contract tests for the disclosure surface.** The suite
  previously skipped in full when no `typos` binary was installed, which is the
  CI runner's state — so nothing about this hook was gated there. The
  disclosure, report-only, cap, and telemetry cases now run against a stub
  binary and execute everywhere; the config-discovery and exclusion cases still
  require a real `typos`.

### Changed

- **The hook now scans read-only before it writes.** `typos --write-changes`
  emits nothing for a correction it applies (verified against typos-cli 1.44.0:
  a fully-fixable file exits 0 with empty stdout after rewriting), so a
  write-only run has no information about what it changed. A read-only pass
  captures the pre-write finding set; the applied set is derived as scan minus
  what survived the write, rather than by guessing which findings typos
  considers safe to auto-fix. Cost is one extra typos invocation only on files
  that actually have findings — measured at roughly 80 ms on a 68 KB file,
  against the handler's 15-second timeout. The read-only pass runs first, so a
  run killed at the timeout between the two passes has modified nothing.
  Both passes are guarded identically: an exit 2 with no output is a typos break,
  not an empty residual set, so a write that broke mid-run is reported as a tool
  break instead of being read as "every finding was applied".
- **Classification is one `jq` pass, not a shell loop.** Process-spawn cost, not
  typos, dominates this hook, and a per-finding loop turns a heavily-corrected
  file into the very defect being fixed: the file is rewritten, the handler's
  15-second timeout fires, and stdout is empty — silent mutation again, on
  exactly the files where the disclosure matters most. The scan set, the
  residual set, the split between them, and the capped display text are all
  produced by a single invocation, so the subprocess count is constant in the
  number of findings. Both finding sets reach `jq` on **stdin**, never as
  `--arg` values: Windows caps a process command line at 32767 characters and
  typos' jsonlines run about 110 bytes per finding, so an argument-passed set
  broke silently somewhere past ~300 corrections — jq never ran and the hook
  degraded to "could not be summarized" on precisely the typo-heavy files the
  disclosure matters most for. A 500-correction file (past that limit, and the
  scale at which the old per-finding loop timed out) is asserted to disclose all
  500 inside the budget; it runs in about 3 seconds against the real binary. The
  residual key is built and compared as a JSON string inside `jq`, so a token
  carrying a shell or glob metacharacter is data throughout.
- **Residual membership is a hash lookup, not a linear scan.** Classifying with
  `index` over an array is quadratic exactly when the residual set is large — a
  minified or generated file where most findings are ambiguous. Measured: 10,000
  all-residual findings took about 15.7 s inside `jq` alone, past the handler's
  15-second timeout, and the file is rewritten *before* classification runs, so
  that timeout lands after the mutation and before any disclosure. The same set
  takes about 0.6 s keyed by object. The scale cases now cover an all-applied
  AND an all-residual set: the applied path alone never touches that branch.
- **The telemetry payload reaches `jq` on stdin too.** `data.findings` and the
  new `data.applied` are uncapped, so roughly a thousand ordinary corrections
  (about 45 KB of JSON) exceeded the same command-line ceiling and the fallback
  would have emitted an envelope reporting `applied: []` for a file this hook
  had just rewritten. A dropped envelope is inside the best-effort telemetry
  contract; one that arrives claiming a heavily-rewritten file was untouched is
  not. The shared `hook::emit_telemetry` still hands the finished payload over
  as an argument (#1595), so an oversized envelope is currently dropped rather
  than delivered — the correct failure direction, and what the scale assertion
  pins.
- **The disclosure is bounded by characters, not only by entry count.** Capping
  the list at ten entries does not cap the message: a token or a correction is
  arbitrary text from the file, so ten long ones overrun the 10,000-character
  `systemMessage` cap and the channel truncates or rejects the disclosure —
  after the file has already been rewritten, which is the one outcome this path
  exists to prevent. Rendered tokens are elided at 60 characters and each
  channel carries a hard ceiling, with the truncation stated in the message.
  The telemetry arrays keep the untruncated values.
- Carriage returns no longer leak into the emitted report. `jq` writes stdout in
  text mode on Windows, so a multi-line value returns CRLF-terminated and
  command substitution strips only the last one, leaving a literal `\r` before
  every remaining newline in the escaped context.

## [0.3.4]

### Changed

- **Test scaffolding: migrated `mktemp -p` temp file/dir creation to the portable `mktemp "$DIR/template"` form.** BSD/macOS `mktemp` has no `-p` flag; the directory now rides in the positional TEMPLATE argument instead, which both GNU and BSD `mktemp` accept identically. Test-only — no hook behavior change. Part of #1527 (`typos-format.test.sh`).

## [0.3.3]

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

## [0.3.2]

### Fixed

- **Headless reconfigure recipe now preserves install scope (#1406).** The `claude plugin
  uninstall` → `claude plugin install ... --config` recipe in `skills/setup/SKILL.md` defaulted
  both halves to `-s user`. When this plugin is installed at `project` or `local` scope, that
  silently uninstalled a separate user-scope record while the effective project/local install kept
  loading, and the reinstall landed at a scope that does not load. Both commands now carry
  `-s <scope>`, sourced from what `claude plugin list` reports for this plugin — the same fix
  already applied to `session-flow` and `rate-limit-guard` in #1393.

## [0.3.1]

### Changed

- Sync of the shared `hook-utils.sh`: the git-option parser distinguishes `--config-env`
  (an env-var name) from `-c`/`--config` (an inline value), and a `--config-env` alias for
  a guarded subcommand is refused by shape rather than by resolving the environment
  variable's value (`#740`). No behavior change for this plugin — it does not inspect git
  config values; shipped so consumers receive the shared library update.

## [0.3.0]

### Added

- **`statusMessage` declared on the hook's `hooks.json` handler** (hook-observability
  convention, `docs/conventions/hook-observability/`): a spinner label ("Fixing
  typos...") now shows while the hook runs. Config-only — no runtime behavior
  change.

## [0.2.0]

### Changed

- **Removed the opt-in config-gate.** The hook now runs `typos --write-changes`
  unconditionally on every `Write`/`Edit`, matching `markdown-format`'s existing
  unconditional pattern — typos ships a built-in spelling dictionary and needs
  no configuration to be useful. Previously the hook silently no-op'd on any
  repo without a hand-authored `typos.toml`/`_typos.toml`/`.typos.toml`/
  `Cargo.toml`/`pyproject.toml`, defeating the plugin's zero-config auto-fix
  purpose on exactly the repos it was meant to help. A consumer typos config,
  when present, is still discovered and honored automatically by typos itself
  (allowlist/exclude) — this hook never re-implemented that discovery and
  still doesn't; only the activation gate is removed.

## [0.1.0]

### Added

- Initial release: a `PostToolUse` hook that runs `typos --write-changes` on
  `Write`/`Edit` of any file, gated on a consumer typos config
  (`typos.toml`/`_typos.toml`/`.typos.toml`/`Cargo.toml`/`pyproject.toml`)
  found by an ancestor walk-up, mirroring the `ruff-format`/`markdown-format`
  plugin pattern. Residual (unfixable) findings surface via `additionalContext`
  with remediation guidance pointing at `extend-words` / `extend-identifiers` /
  `extend-ignore-re` allowlist entries. Advisory only — never blocks the edit.
- `hook-telemetry` conformance: emits a schema-valid envelope
  (`docs/conventions/hook-telemetry/data/typos-format.schema.json`) via the
  shared `hook::emit_telemetry` helper.
- `/typos-format:setup check|apply` skill for prerequisite verification.
