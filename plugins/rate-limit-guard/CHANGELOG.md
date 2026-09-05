# Changelog

All notable changes to the `rate-limit-guard` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.8.0]

### Added

- **The tee snapshot names the account whose windows it carries.** The drain stamps
  `account: {"email": "<address>"}` at the top level, read from Claude Code's own
  `.oauthAccount.emailAddress` in `${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json`. A reader can now tell
  whether a snapshot describes the account it is running under, which is the writer-side half of the
  account-identity design; reader-side invalidation of latched state and the lane-floor re-audit
  remain `TODO(#1218)` follow-up, so the multi-account gap narrows rather than closes.

  **Mislabeling is worse than absence, so the field is omitted in four cases:** the state file is
  missing, unreadable, or holds no email-shaped value; the stdin payload already carried a top-level
  `account*` key (that one wins, and the writer adds nothing beside it); the state file was modified
  **after** the chosen record's spool file, which means a switch may have happened between the
  observation and the flush; or the writer ran on a path with no spool to date that comparison
  against (`RLG_TEE_ASYNC=1`, or bash below 4.2). Statusline output and exit codes are unchanged in
  every case, as they are for every other tee outcome.

  **Cost is one process per 30-second drain, and the render path stays fork-free** (the zero-fork
  trace case still passes). Mechanism measured on the target desktop, 2026-09-04, against an 88 KB
  state file: bash `$(<file)` plus parameter-expansion extraction 3.6–4.0 s, unusable on any path;
  `jq -r` over stdin 35 ms; `claude auth status --json` 175 ms. Bash opens the file and jq reads
  stdin, so the Windows MSYS-path limitation that keeps every other file out of jq's argv does not
  apply. The batch jq pass gained two output lines for this — the chosen record's shard name, which
  is what the staleness comparison dates against, and a structural `keys_unsorted` test for an
  existing account key, asked the same way the window-bearing verdict is asked with `has()` rather
  than as a substring scan.

  `.oauthAccount.emailAddress` is **internal CLI state**, not a documented surface: the reader
  contract carries it as a recheck trigger, and the untrusted-value rule applies to the field
  unchanged. The writer's validation (an `@`, no double quote, backslash, or control character,
  3–254 characters) is a shape whitelist that keeps its own JSON well-formed, not an assertion that
  the address is real. (Refs #1218)

### Fixed

- **A native jq's CRLF no longer decides which of the tee's own verdicts is readable.** Every line
  after the payload in the shared jq pass is now CR-stripped in `_rlg_absorb_jq_lines`. A native jq
  on Windows terminates its output lines with CRLF and `read -r` splits on LF only, so a token line
  arrived as `true\r` and compared equal to nothing; only the LAST line was reliably clean, because
  MSYS command substitution drops the trailing CRLF. Which verdict was correct therefore depended on
  how many lines the pass emitted and on whether the enablement verdict was empty — with an empty
  verdict the window-bearing token was clean and the verdict was not, and with a configured verdict
  the reverse. Adding two lines for the account field would have left both wrong, which is how this
  surfaced. The payload keeps its CR deliberately: the snapshot's bytes stay what jq wrote, and the
  no-change compare already normalizes its key rather than the payload. Invisible on a Linux runner,
  where jq emits LF; a case driven by the suite's existing CRLF `jq` shim now covers it on every
  platform.

### Changed

- **The operable floor's staleness bullet no longer claims the file carries no account identifier.**
  Amended in `reference/reader-contract.md` and in all six inlined copies in the same change, which
  `scripts/check-loop-lane-floor-drift.sh` proves moved together. A write is still the signal that
  the windows changed under you; it is no longer the *only* one.

## [0.7.35]

### Changed

- **Telemetry envelope at contract 1.1: the session id rides on the spine.**
  The synced `hooks/hook-utils.sh` copies the payload's `session_id`,
  `prompt_id`, `tool_use_id` and `agent_id` from the buffered `INPUT` onto
  every envelope this plugin's hook emits, each only when present as a plain
  id, so the claude-ops per-session report lists this hook with no change to
  the hook itself (#3758). `schema_version` reads `1.1`; no hook behavior
  changes.

## [0.7.34]

### Changed

- setup: dropped the ADR rationale for the bespoke legacy detection, restated the compose warning
  as the present-tense failure it prevents, and lowercased the all-caps emphasis.
- setup: the shared `legacy-statusline-detect.md` and `unwrap-before-compose.md` spokes drop the
  wrong `< 0.2.0` shim boundary, the ADR rationale, the incident narration, and the all-caps
  emphasis; edited at the context-guard source and re-synced.
- reference/reader-contract.md: replaced the `TODO(#1218)` tracker pointer with a present-tense
  statement of the account-identity gap, and replaced the hardcoded consumer counts with a pointer
  to the drift-check registry that owns the roster.

Applied from the 2026-09 prompt-audit against Claude Fable 5.1 (docs/specs/prompt-audit-skills-2026-09.md).

## [0.7.33]

### Changed

- **Vendored `hook-utils.sh` drops two `buffer_stdin` startup subshells and a
  `tr` exec on every `repo_root`.** Timeout and slice resolution write into
  caller variables (`printf -v`) instead of `$( )` / process substitution —
  GNU Bash forks a subshell for both even when the body is builtins only.
  `hook::repo_root` strips CR with parameter expansion, the same substitution
  `buffer_stdin` already uses for the payload. New `hook::json_str_object_to`
  builds compact string-field objects without jq, for telemetry data builders
  that only carry strings. Same verdicts; the copy is bumped because
  `scripts/sync-hook-utils.sh` keeps every carrying plugin byte-identical.

## [0.7.32]

### Added

- **`hooks/hooks.json` carries a top-level `description`.** The hooks reference
  documents the field as optional, and every hook set in this marketplace omitted
  it; it is the surface an operator reads when deciding what a plugin does to
  their session. One line naming what this plugin's hook set does. (#3719)

## [0.7.31]

### Changed

- **The statusline tee's five copies of the stamp-read idiom became one
  `_rlg_read_stamp` helper.** Every one of the five sites is on a render path,
  so the helper is builtins throughout and no call site pays a process. The
  validation is the load-bearing half and is now spelled once: bash evaluates
  the TEXT of an arithmetic operand, so an unvalidated stamp shaped like
  `a[$(cmd)]` would run `cmd` on every render. Spawn counts were measured with
  `strace` on every path rather than assumed, and no path increased.
- **The Stop hook's rotation drops a fork and merges two cleanup paths.**
  `rotate_events` piped `wc -l` through `tr -d ' \r'` to strip BSD padding and a
  Windows CR; a parameter expansion does the same on a hook that fires on every
  stop. The `tail`-then-`mv` pair had one cleanup arm per failure; a failing
  `tail` leaves the redirection's empty temp and a failing `mv` leaves the
  written one, while a successful `mv` has already consumed it, so one `rm -f`
  after the combined success test covers both. Rotation threshold, retained
  record count and exit status are unchanged.
- **`bench.test.sh` folds two failing-render cases into `expect_render_abort`.**
  Both lanes are now checked the same way against the same bad entry, which is
  what the pair was asserting.

## [0.7.30]

### Changed

- **`_rlg_spool_dispatch` derives its spool path instead of repeating it.** The
  two paths were declared in one `local` statement that spelled the parent
  directory out twice; `dir` is now declared first and `spool` derived from it.
  The single-statement form was safe only because it repeated the literal: bash
  does not expand a same-statement `local` assignment, so deriving `spool` from
  `$dir` in that same statement would have left it empty and, under this file's
  `set -u`, killed the statusline with an unbound-variable error on every render.
  Verified by building that failing variant and running it. Hot-path cost is
  unchanged, measured with `strace`: identical execve, clone and openat counts
  across three modes, cold and primed, with the full syscall multiset matching.
  Emitted bytes byte-identical across 27 artifact comparisons.
- **Test and comment tidyings.** `statusline-tee.test.sh` collapses four copies
  of a find-and-count pipeline into one helper, mutation-tested at all four call
  sites including a plausible off-by-one. Five comments in `statusline-tee.sh`
  and `bench.test.sh` drop history narration for the present-tense mechanism,
  each rewritten claim executed rather than assumed, with every measurement kept.

## [0.7.29]

### Changed

- **The statusline-tee cancellation cases park their `mv` shim for two seconds
  instead of ten.** Bash defers the TERM trap until the foreground `mv`
  returns, so the shim's own sleep was the floor for both cancellation cases
  and the suite spent most of its wall time waiting on a delay that proved
  nothing. Two seconds exercises the same cancellation window behind the same
  readiness marker. Test-side only; no hook, script or shipped behaviour
  changes.

## [0.7.28]

### Changed

- **Vendored `hook-utils.sh` builds the telemetry envelope and reads `file_path`
  with shell builtins.** `hook::emit_telemetry` no longer spawns two jq
  processes, a mktemp and an rm per run: the envelope is assembled in the shell
  as one compact line (the same document jq produced, now `jq -c` shaped), with
  jq kept only as the fallback for a data object the builtin compactor cannot
  prove. `hook::read_file_path` takes `.tool_input.file_path` without jq on the
  well-formed payload shape and resolves the file, project root and temp roots
  with one batched `realpath` instead of one process each. Same verdicts, same
  emitted path, same sink record; phase 4b of the hook-performance program
  (#3623). The copy is bumped because `scripts/sync-hook-utils.sh` keeps every
  carrying plugin byte-identical.

## [0.7.27]

### Changed

- **`statusline-tee.sh` skips the snapshot rename when nothing changed, and sweeps the spool on a
  cadence.** Profiling the wired render path found nothing left to cut there: the spool has made
  every non-elected refresh fork-free, which the suite already asserted by tracing one, so the whole
  remaining cost sits in the drain that runs once per cadence. That drain spent ten process
  creations every time regardless of whether the payload had moved. Two cuts. A refresh whose body
  is byte-identical to the snapshot on disk, `captured_at` aside, now takes no lock, stages no temp
  file and performs no rename. And the spool's 15-minute record sweep moved to a 5-minute cadence,
  since it was spending a `find` twice a minute to enforce a fifteen-minute floor. The deterministic
  result is the process count: a drain on an unchanged payload runs three external commands where it
  ran seven, losing the rename, the snapshot lock's `mkdir` and `rmdir`, and the sweep's `find`.
  Timed on Windows/MSYS with both tees interleaved in one loop so they meet the same load, the drain
  falls from 8 to 10 spawn-equivalents over the bare render down to 5 to 6, across two runs of 12
  trials whose spawn floors were 57 ms and 45 ms. The steady render is unchanged, 1.2 against 1.1
  spawn-equivalents on the same runs, well inside a bar of 2, because the spool already left it
  nothing to cut.
- **The no-change skip is bounded, because the staleness rule is written against `captured_at`.**
  `reference/reader-contract.md` makes a snapshot stale on a `captured_at` older than ten minutes
  and says explicitly that the rule reads that field and never the file's mtime. An unbounded skip
  would therefore starve `captured_at` on a machine whose windows are genuinely fresh but unmoving,
  one idle session with `refreshInterval` still ticking, and silently demote the whole guard to
  reactive-only: the same damage the windowless-writer preservation check exists to prevent,
  arriving through a different door. A `.last-write` stamp, written with a builtin after a
  successful rename, caps the skip at half the staleness budget. The compare runs before the lock,
  since a compare under the lock would already have paid two of the three processes it avoids, and
  after the temp sweep, so a refresh that skips its write still reclaims a killed session's orphan.
  A trailing CR is stripped from both sides of the comparison: a native `jq` on Windows ends its
  lines with CRLF, so the payload line keeps its CR under `read -r` and carries it into the file,
  while what the read-back side holds depends on the bash build (MSYS bash drops a trailing CRLF
  from `$(<file)`, a POSIX bash keeps the CR) and on which `jq` wrote the snapshot on disk. Any of
  those leaves a CR on one side only, and the two sides would never have compared equal on the one
  platform the skip exists for. The bytes the writer emits are unchanged. The atomic
  temp-plus-rename write, its `EACCES` retry, and both lock disciplines are untouched, and the same
  payload fed to this tee and to the previous one writes snapshots identical under
  `jq -S 'del(.captured_at)'`.
- **Every tuning knob is validated before it reaches bash arithmetic.** Bash evaluates the text of
  an arithmetic operand, so `(( now - last < $KNOB ))` with an unvalidated environment value shaped
  like `BASH_VERSINFO[$(cmd)0]` runs `cmd` on every render. `RLG_TEE_NOCHANGE_FLOOR`,
  `RLG_TEE_SWEEP_INTERVAL` and `RLG_TEE_DISABLED_RECHECK` are now checked against `^[0-9]+$` and
  fall back to their defaults otherwise, exactly as `RLG_TEE_DRAIN_INTERVAL` and every stamp read
  from disk already were. The check is a builtin, so the traced zero-fork render path is unchanged.
- **The reader contract and README describe the bounded skip.** Both had kept the earlier promise
  that the snapshot trails the newest refresh by at most 30 seconds, and the script header still
  said every refresh writes. They now say what holds: a changed payload reaches the snapshot within
  the drain cadence, an unchanged one may leave the file and its `captured_at` untouched for up to
  the 300-second floor, and the staleness rule itself is unchanged.
- **Nine new suite cases.** The skip fires on an identical payload inside the floor, does not
  misfire on a changed one, expires with the floor so `captured_at` stays fresh, and the spool sweep
  honours its cadence while still reclaiming a dead session's aged record. Proven by mtime against a
  sentinel rather than by content, since the body a skipped refresh would have written is by
  definition byte-identical to the one already there. Each of the three environment knobs is fed a
  value that would create a file if it ever reached the arithmetic, and the suite asserts the file
  is absent, the default behaviour holds, and the passthrough survives; the shape subscripts an
  array bash always sets, because a shape that merely aborted the shell under `set -u` would leave
  every file untouched and pass vacuously. And a PATH `jq` shim that re-emits CRLF line endings
  proves the skip still fires with a CR on the payload side only and on the disk side only.

## [0.7.26]

### Changed

- **Options reference cites the plugin-reconfiguration convention.** The generated
  How-to-set-these block no longer restates the 2.1.240 verified-version record.

## [0.7.25]

### Changed

- **setup: unwrap-before-compose matches context-guard, then shares the spoke.** The inline
  shell-syntax guard treated bare quoting as a wrap trigger, the bug context-guard already
  fixed with `type -P` / `type -t`. Peel and wrap rules now live in
  `reference/unwrap-before-compose.md`, synced byte-identical from context-guard.

## [0.7.24]

### Changed

- setup's legacy-statusline detection (shim-revision ladder, legacy version-pinned wiring) moves to the shared synced spoke reference/legacy-statusline-detect.md, synced from context-guard, with a machine-scope bespoke rationale (customization-consistency Phase 2c)

## [0.7.23]

### Changed

- **setup:** cite the plugin-reconfiguration convention for the native
  `/plugin configure` / headless `--config` path instead of restating the
  verified-version record inline.

## [0.7.22]

### Changed

- **`reference/reader-contract.md` gains an observable recheck trigger.** The file carried dated
  claims about the statusline `rate_limits` payload with no stated event obliging re-derivation. It
  now names them: the `statusline` doc changing its `rate_limits` schema, or Claude Code shipping
  statusline wiring or a persistent filesystem in cloud and remote-session containers, which is the
  event the file's own "Documented residual" section already treats as the path to proactive mode.
  Additive only.

## [0.7.21]

### Fixed

- **`statusline-tee.sh` passes payloads over 1MiB through to the wrapped statusline intact.** The
  stdin reader was a single bounded `read -N 1048576`, so anything past the first 1MiB never
  reached the wrapped command. Ported the sibling context-guard tee's builtin-only
  read-until-EOF loop, keeping the documented stalled-pipe timeout boundary; a new suite case
  proves a 1.5MB payload reaches the wrapped command byte-for-byte and is still teed. Zero new
  processes: the suite's zero-fork xtrace assertions still pass and the bench spawn floor is
  unchanged.

### Changed

- **`statusline-tee.sh` hardens its snapshot temp write.** The temp name gains a second `$RANDOM`
  of entropy and the write happens under `set -o noclobber` inside the existing umask subshell,
  so a pre-planted symlink at the temp path is refused instead of followed. The chmod-700
  directory, trap reclaim, and mv-retry machinery are unchanged. Ported from the context-guard
  sibling. Suite grows from 96 to 98 checks, all passing.

## [0.7.20]

### Changed

- **Vendored `hook-utils.sh` gained `hook::repo_relative_path`.** The shared lib
  now owns the repo-relative path computation twelve sibling hooks had each
  hand-copied, together with the absolute-path degrade only four of those twelve
  copies carried (#1133). This plugin's hooks do not call it; the copy is bumped
  because `scripts/sync-hook-utils.sh` keeps every carrying plugin
  byte-identical.

## [0.7.19]

### Added

- **The inline-floor mandate is enforced instead of asserted.** `scripts/check-loop-lane-floor-drift.sh`
  in the marketplace repository extracts the "Operable floor" block from this file and compares it
  against an explicit registry of the six surfaces that inline it, running as the
  `loop-lane-floor-drift-gate` CI lane. The `Consumers` section now names that check and the three
  non-lane consumers it covers. Nothing enforced the mandate before: the general copy-drift gate
  skips `SKILL.md` by basename and clusters copies by identical path-within-plugin, and these six
  sit at six unrelated paths.
- **The same check also discovers copies nobody registered.** Before comparing anything it scans
  every tracked file for the floor's opening bullet and fails on any carrier outside its registry,
  so a seventh consumer inlining this block cannot sit unwatched until the next contract change
  strands it. The registry stays, because it carries each consumer's comparison mode.
- **Why this lands after 0.7.18 rather than with it.** 0.7.18 reconciled the drift by hand, from the
  other direction, while this check was in review. That is the argument for the check rather than an
  objection to it: the same two sentence breaks were found and repaired twice, independently, weeks
  apart, because nothing was watching the block. The floor block is unchanged here; 0.7.18's
  wording stands as the one this gate now holds every copy to.

### Changed

- **`setup`'s tee-freshness probe stops restating the staleness window.** Step 4 named the
  10-minute value inline, which is a copy of a floor constant sitting outside the block the drift
  check compares, so nothing would have moved it if the contract changed. It now points at the
  operable floor for the value. Same probe, same verdicts.

## [0.7.18]

### Changed

- **Rate-limit-guard inline floor restored to byte-identity.** The loop-lane convention requires the
  floor's values identical across the three consuming lanes; hashing those three plus the reader
  contract they cite and `extract-ssot`'s orchestrated-mode consumer found two distinct texts. The
  drift traces to two de-slop shards, which made the same two substitutions and so produced one
  drifted form rather than two; one of those substitutions replaced a clause-joining dash with a
  comma and left a splice. All five carriers now hash identically on an em-dash-free, grammatical
  form. Whole-repo extract-ssot sweep.

- **`setup`: rejoined an orphaned clause in the never-writes boundary.** The sentence ended with a
  period and then continued lowercase ("...settings surface. the printed edit is the operator's to
  apply."). The `context-guard` sibling carries the identical slot joined with a semicolon, and this
  one now matches it. Whole-repo extract-ssot sweep.

## [0.7.17]

### Changed

- **Authoring-doctrine pass over `README.md`.** Fixed sentences that parsed two ways. Every edit was verified against the file by an agent that did not propose it. Prose only; no behavior, contract, or trigger phrase changed.

## [0.7.16]

### Changed

- **Shared `hook-utils.sh` comment cleanup.** Comment-only sync from `lib/hook-utils.sh`: history-narration comments rewritten as present-tense rules; no behavior change.

## [0.7.15]

### Changed

- **`statusline-tee.sh` names its bash-version and settings-read logic.** Repeated inline
  `BASH_VERSINFO` comparisons became a `_rlg_bash_at_least` helper (keeping each call site's own
  4.1/4.2 floor), the duplicated settings-JSON read became a `_rlg_read_settings_json` helper
  (non-caching, same reads), and an append uses `lines+=()`. Behavior is unchanged. Code-tidying
  sweep, behavior-preserving.

## [0.7.14]

### Changed

- **The generated options block sits under `## Configuration`.** It was under `## Consumers`, below
  the section that already documents configuration. The generated table itself is unchanged; only
  its placement moved. Docs-hygiene sweep, L8-write-for-humans.

## [0.7.13]

### Changed

- **Options-reference regeneration.** `scripts/sync-plugin-options-docs.py` dropped the
  phrase `in order to` from its shared options template, per the repo's own
  write-for-humans style rule that the phrase is just `to`. The generated options
  block in `README.md` regenerated with the shorter wording; no other change.

## [0.7.12]

### Changed

- **Behavior-preserving simplification pass (repo-wide batch-simplify).** `bench/bench-load.sh`
  reads the sample files once into a variable feeding both aggregation passes (equivalence
  rests on the sole writer's `printf '%s\n'` newline termination, verified; empty-glob and
  blank-line cases proven identical), `bench/lib-bench.sh`'s median collapses its
  sorted-string plus manual re-read into `mapfile -t` (17-case differential corpus, zero
  diffs), and `scripts/statusline-tee.test.sh` drops a constant-false `sess-gate` disjunct
  (the id appears nowhere as an input; removal moves the DIFFERS cluster further from
  convergence). Suites green (13 + 96); cross-plugin drift gate green; live hook and
  statusline sources untouched.

## [0.7.11]

### Changed

- **Instruction-surface de-slop (#2891, guardrails cluster).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change. The generated options block is ignore-fenced because
  `scripts/sync-plugin-options-docs.py` still emits em dashes from its shared template.

## [0.7.10]

### Fixed

- **Vendored `hook-utils.sh` skip latch (#3128).** The shared notice latch now
  keys on session and agent (a subagent gets its own first notice), stores a
  skip count in the marker (independent of `HOOK_TELEMETRY_SINK`), and emits a
  one-line re-notice every 8 skips instead of going silent after the first.
  The first `PATH probed:` dump omits other plugins' bin dirs. Copies stay
  byte-identical via `scripts/sync-hook-utils.sh`.

## [0.7.9]

### Changed

- **setup:** normalized restated setup-contract prose (preamble, probe-ladder
  opening, never-writes boundary, and/or headless-reconfigure recipe as present) to the
  canonical fleet wording, keeping the operable text inline with a provenance-only citation
  (whole-repo extract-ssot batch, #2698).

## [0.7.8]

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

## [0.7.7]

### Changed

- Sync `hook-utils.sh` from `lib/` — two header-echo comments removed in
  `hook::emit_telemetry` (comment-only; no behavior change).

## [0.7.6]

### Changed

- Behavior-preserving simplifications from the repository-wide batch-simplify pass:
  duplicated helpers folded, dead code and redundant constructs removed, no functional
  change. Every group was verified by a fresh-context verifier agent against the
  plugin's own test suite.

## [0.7.5]

### Added

- **Reader contract: cloud / remote degraded mode.** Documents that cloud and remote-session
  containers typically have no statusline producer and an ephemeral filesystem, so the tee path is
  absent by expectation and capability detection classifies **unknown → reactive-only**. Names the
  reactive signals a cloud consumer may use (own-session rate-limit errors, live sibling-automation
  429s, `stop-events.jsonl` when present), the orchestration thin-by-default fallback when headroom
  is unobservable, and the documented residual that a live cloud statusline/producer path is out of
  scope until one exists (#2697, #2736, #2747).

## [0.7.4]

### Added

- **bench:** commit the benchmark harness that produced #2521's render-path measurements
  (`bench/bench-idle.sh`, `bench/bench-load.sh`, `bench/trace-probe.sh`, `bench/lib-bench.sh`),
  adapted to run from a clean checkout against the repo's own tee, with `bench/README.md`
  recording the baseline numbers, platform, and spawn-floor method, and `bench/bench.test.sh`
  smoke-testing the harness in CI — behaviour and output shape only, never timing (#2582).
  Review hardening over the scratch originals: fork-free timer reads (`printf -v`, no command
  substitution), a loud bash >= 5.0 refusal instead of an `EPOCHREALTIME` unbound-variable
  abort, render failures abort a lane instead of being timed, and the load lane's
  pad-to-one-second arithmetic no longer sleeps 0.1 s when a render took 0 ms.

## [0.7.3]

### Changed

- **Docs:** actionable `/plugin configure` guidance now uses the marketplace-qualified form
  (`<plugin>@<marketplace>`; generated option blocks use `@<marketplace>`) per
  [`docs/extensibility-contract-smoke-tests.md`](../../docs/extensibility-contract-smoke-tests.md)
  Test E (#1360). Targetless references to the flow stay unqualified.

## [0.7.2]

### Fixed

- **hook-utils:** distinguish unresolved `physical_path`/`repo_root` answers and honor unquoted `#` in `bash_parse_segments` (#1487).

## [0.7.1]

### Fixed

- **hook-utils:** scope `read_file_path` to git worktrees when project dir unset (#1091).

## [0.7.0]

### Changed

- **The statusline refresh no longer writes the snapshot; it records to a spool and one
  elected refresh per 30 seconds flushes the batch.** Measured same-window here
  (Windows/MSYS, n=9): `render.sh` alone 234.4 ms, `render.sh` behind this wrapper
  1047.1 ms. The wrapper dominated, and the dominant term inside it was process
  creation — a cost MSYS has no cheap primitive for, on a path that fires on every
  assistant message AND every `refreshInterval` tick, once per open session. 0.6.x
  made that work cheaper (nine spawns to four); this release takes it off the render
  path instead. The common refresh now runs **zero external processes and zero
  subshells**, asserted by an `xtrace` of a non-elected render rather than by reading
  the code.

  What a refresh does now: extract `session_id` by parameter expansion, strip CR/LF
  (a JSON string cannot contain either, so this is lossless), stamp the epoch with
  `printf -v '%(%s)T'`, and overwrite `~/.claude/rate-limit-guard/spool/<session>.json`
  with one line. All builtins.

  **Per-session files, not a shared append spool.** POSIX specifies atomicity for
  concurrent writes to pipes up to `PIPE_BUF` and explicitly leaves regular-file
  behaviour unspecified; through Cygwin/MSYS the observed no-interleave bound on
  appends is around a kilobyte while statusline payloads are multiple kilobytes, and
  bash's buffered builtin output can split one large record across syscalls anyway.
  Atomicity therefore comes from **file disjointness** — no two writers ever share a
  file, each record is one line written with a truncating `>` — instead of from an
  argument about write sizes. A record torn by a kill mid-write fails `fromjson` in
  the drain and is dropped, which is covered by a test.

  **The filename is a shard key, never trusted data.** `session_id` arrives in the
  harness payload; it must match `^[A-Za-z0-9._-]{1,64}$` and not begin with a dot, or
  it shards to the literal name `misc`. Traversal attempts, embedded quotes,
  200-character values and JSON nulls are all covered.

  **Election is stamp-based, and the elected refresh drains in-process.** There is no
  timer to hang this on: Claude Code hooks are strictly event-driven and none fires on
  a schedule (<https://code.claude.com/docs/en/hooks.md>), an OS scheduler would mean
  three mechanisms across three platforms, and a resident lock-holder would have to be
  forked off a render — the exact cost being removed — and would be killed with it,
  since Claude Code cancels in-flight statusline scripts. So the renders are the clock:
  whichever finds `spool/.last-drain` older than the cadence takes `spool/.drain.lock`,
  re-reads the stamp under it (a herd collapses for one failed `mkdir`), and flushes.
  The drain uses its OWN lock rather than the snapshot lock, so `tee_snapshot` keeps
  the concurrent-writer lock, the atomic temp-then-rename and the windowless-writer
  preservation check exactly as they were.

  **The snapshot body is byte-identical apart from `captured_at`**, proven by
  `diff <(jq -S 'del(.captured_at)' pristine) <(jq -S 'del(.captured_at)' patched)`.
  The body projection is now one shared jq function called by both the live probe and
  the drain, so the two cannot drift. `captured_at` is the **observation time of the
  chosen record**, never the flush time — which is what lets a windowless refresh
  flush a window-bearing sibling's record without faking freshness.

  **Reader-visible change, inside the existing contract:** the contract file now trails
  the newest refresh on the machine by up to 30 seconds instead of being rewritten on
  every refresh. The reader contract budgets ten minutes of staleness and its operable
  floor values are unchanged; `reference/reader-contract.md` documents the cadence,
  the `spool/` inventory and the `.tee-disabled` marker.

  **The enablement gate still gates the write**, but it cannot be evaluated on the
  render path — reading settings costs a `jq`. A drain that reads
  `rate_limit_guard_enabled: false` writes an epoch-stamped `.tee-disabled` marker and
  drops the spool; refreshes then stop recording on one builtin test. The marker
  expires, so a re-enabled plugin recovers on its own without a restart.

  Bash 4.2 is the floor (`%(%s)T` is a 4.2 builtin). Below it — macOS bash 3.2, where
  `fork` is cheap and this problem does not arise — the previous synchronous path runs
  untouched, and `RLG_TEE_ASYNC=1` keeps its current behaviour on every version.

  All 75 pre-existing assertions pass unmodified; the suite is now 96.

## [0.6.3]

### Changed

- **Synced `hook-utils.sh`:** write `emit_telemetry`'s `data` payload to a temp file instead of passing it via `--argjson`, so payloads above the Windows command-line cap are not dropped (#1595).

## [0.6.2]

### Changed

- **Synced `hook-utils.sh`:** peel sudo clustered short options for chdir resolution (#1811); widen the valueless-short peel set and keep `-h` value-taking.

## [0.6.1]

### Changed

- Cut statusline tee from 9 process spawns to 4.

- **The settings document reaches `jq` through the environment, not through argv
  and not through a temp file.** A settings file can hold credentials, and argv is
  world-readable via `ps`/`/proc/<pid>/cmdline` for the life of the process while
  `/proc/<pid>/environ` is owner-only. Both readers — `_rlg_settings_option`, which
  the managed scope calls on every refresh wherever a `managed-settings.json`
  exists, and `_rlg_probe` — now bind `$doc` from `env.RLG_SETTINGS_DOC` through one
  shared prelude, so neither can drift back.

  This also restores the fail-OPEN behaviour on a malformed settings file. Parsing
  the document jq-side (`--argjson`, `--slurpfile`) aborts the whole invocation
  before the filter runs, which took the snapshot down with the verdict; parsing it
  filter-side under `try` yields an empty verdict and leaves the snapshot alone.
  And it keeps the read off any jq-opened path: a native jq on Windows cannot open
  an MSYS-style path, and `$TMPDIR` under MSYS is one.

  Net spawns: measured against the slurpfile form on the same machine, a
  steady-state refresh drops two external commands (`mktemp` and `rm`, which that
  form added) and one subshell — 7 distinct `BASHPID`s to 6. The externals that
  remain are the ones 0.6.0 documented as the contract itself.

## [0.6.0]

### Changed

- **The statusline tee cost ~450 ms of process spawns on every refresh; it now costs ~180 ms,
  with no change to what it writes.** This script runs once per assistant message AND once per
  `refreshInterval` tick, in every open session, so its cost is multiplied by how many sessions
  the user keeps open — at ten sessions on `refreshInterval: 1` it was the dominant term in
  statusline latency. Nothing about the snapshot changed: the contract file's body is
  byte-identical, and the 71 pre-existing assertions pass unmodified.

  Per refresh, external commands went from nine to four and subshell forks from eleven to six.
  The four that remain are the contract itself and are deliberately untouched — one `jq` to build
  the snapshot, `mkdir`/`rmdir` for the concurrent-writer lock, and `mv` for the atomic rename.
  What went:

  - **Three `jq` spawns became one.** A new `_rlg_probe` produces the snapshot body, the
    window-bearing verdict and the user-scope enablement verdict in a single pass. The settings
    document is read by bash (`$(<file)`, which bash performs without forking) and handed over as
    `--argjson`, never opened by jq — preserving the existing reason the read was a shell
    redirection: a native jq on Windows cannot open an MSYS-style path. The verdict filter is now
    a single constant shared by the probe and `_rlg_settings_option`, so the two cannot drift.
  - **`_rlg_tee_enabled` consumes the probed verdict**, with a fallback to its own read when no
    probe has run, so a direct call to it (no `main`) behaves exactly as before. The gate moved
    next to the write it governs, which is the only thing it decides.
  - **`uname` is no longer spawned to discover that no managed-settings file exists.**
    `_rlg_managed_settings_files` now tests all three candidate locations with builtins first;
    the platform table still decides whenever one is actually present.
  - **`date -u` became `TZ=UTC printf -v … '%(…)T'`**, a bash builtin, output verified identical.
  - **`mkdir -p` and `chmod 700` on the contract directory run only when it is absent.**
    Both were unconditional, and both are processes re-asserting a state that already held.

  One deliberate behavioural tradeoff, called out because it is a real one: the contract
  directory's owner-only mode is now asserted at creation instead of re-asserted on every refresh,
  so a mode that a user or another tool later loosens is no longer silently corrected. No builtin
  can read a file mode, so the alternative is a `stat` process per refresh — exactly the cost being
  removed.

### Added

- **`RLG_TEE_ASYNC=1` detaches the snapshot from the render. Off by default, and the measurements
  say why.** The snapshot is a side effect — nothing the wrapped command prints depends on it, and
  the reader contract budgets ten minutes of staleness — so it is a natural candidate for running
  out of line. It skips no work: every refresh still takes the lock and writes.

  Detaching is a clear win for one session and a clear loss for many. MSYS has no native `fork()`,
  so forking a bash subshell holding the payload was measured at 75–200 ms against ~24 ms to exec
  a small binary. Detaching does not make the work cheaper; it buys back the render's critical path
  by paying a fork more expensive than the execs it steps around, and it lets successive refreshes
  overlap instead of serialise. Measured (Windows, 24 cores, statusline + tee):

  |                                   | sync (default) | async      |
  | --------------------------------- | -------------- | ---------- |
  | one session, refreshes 1 s apart  | 660 ms         | **222 ms** |
  | ten sessions at 1 Hz, median      | **2265 ms**    | 4476 ms    |
  | ten sessions, peak bash processes | **50**         | 71         |

  Sessions, not refresh rate, is the variable that decides. Turn it on if you run one or two
  windows; leave it off if you run many. The durable fix removes the cost instead of moving it —
  the render appending its payload to a spool file with zero forks, drained by one periodic
  writer — and that is not this flag.

  When enabled, detachment is threefold and each part is load-bearing: stdout and stderr go to
  `/dev/null` (otherwise the child holds the statusline pipe open and Claude Code waits for EOF
  long after the render finished, cancelling out the point), stdin is closed, and the job is
  disowned. A cancelled refresh can now be killed mid-write, which is the case the existing
  temp-file-plus-rename, reclaim traps and age-filtered sweep were already built for.

- **Four assertions covering the detached path** (75 total, up from 71): stdout carries only the
  wrapped command's output, the snapshot still lands, it carries the session's windows, and a
  reader consuming stdout to EOF is not made to wait on the child. The suite runs the default
  synchronous path everywhere else, so assertions that a snapshot was *not* written keep their
  meaning instead of passing vacuously against a race.

## [0.5.10]

### Changed

- **Synced `hook-utils.sh`:** refuse sub-minimum `stdin_read_timeout` values (#1883).

## [0.5.9]

### Changed

- **Synced `hook-utils.sh`:** `hook::jq_fields` returns 2 when jq is present but cannot parse the payload (#2157).

## [0.5.8]

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

## [0.5.7]

### Fixed

- **The statusline tee's kill switch read only one of the three scopes the contract names, so a
  managed policy was silently ignored.** `0.5.6` moved the gate onto a direct settings read but
  implemented the user settings file alone. This repository's own
  [hook-config-delivery](../../docs/conventions/hook-config-delivery/README.md) convention, fact 5,
  states that `pluginConfigs` is read back from **user settings, the `--settings` flag, and managed
  settings** — so an organization that set `rate_limit_guard_enabled: false` in
  `managed-settings.json` had the tee keep writing anyway. Managed settings are the
  highest-precedence scope and cannot be overridden by any user or project scope, which is exactly
  what makes that a policy bypass rather than a cosmetic omission.

  The gate now reads managed settings too, mirroring the channel-F exemplars the convention points
  at — `plugins/disk-hygiene/lib/killswitch_config.py` and the sibling bash reader
  `plugins/autonomy/hooks/lane-stop-gate-lib.sh`: the fixed per-platform root-owned paths
  (`/Library/Application Support/ClaudeCode/`, `/etc/claude-code/`, `C:/Program Files/ClaudeCode/`)
  selected by `uname -s`, plus the `managed-settings.d/` drop-ins in sorted order with later files
  overriding earlier ones. The Windows path is the literal absolute path the docs give, never
  `%ProgramFiles%`-derived, and every resolved path is re-checked as absolute — an
  environment-derived or relative base would let a repository redirect the one scope that outranks
  every other.

  **Precedence is now managed → user settings → environment**, highest first. Managed wins because
  a gate a user or a repository can out-vote is not a policy control. The environment channel also
  moved *below* user settings, which is a second behaviour change and deliberate: it is retained
  only in case `CLAUDE_PLUGIN_OPTION_RATE_LIMIT_GUARD_ENABLED` is ever delivered to a `statusLine`
  process, and for an unconfigured key a repository `.claude/settings.json` `env` block populates it
  freely with no provenance (same convention, fact 4), so it must not out-vote a value a real
  settings scope configured. Every previously held property survives: the tee fails **open** on a
  missing file, missing `jq`, malformed JSON, or an unrecognized platform; the `pluginConfigs` key
  is still matched by prefix so a fork or private catalog works; and the jq filter still avoids
  `// empty` on the value — the alternative operator treats `false` as falsy and would discard the
  exact value this gate exists to detect — using `tostring` plus an explicit `length == 0` emptiness
  test instead.

  **Residuals (accepted, unchanged by this release).** The *user* settings file is still located
  from `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` rather than channel F's install-cache anchor, so a
  repository `env` block that redirects `CLAUDE_CONFIG_DIR` can still hide a user-scope `false`;
  and a value supplied only through a session `--settings` file is invisible to any on-disk read
  (channel F's own documented residual). Neither reaches the managed verdict, which is
  environment-independent by construction, so the scope an organization actually enforces with is
  now sound.

- **Nothing tested the gate at all.** `scripts/statusline-tee.test.sh` had no coverage of
  `_rlg_tee_enabled` under either implementation; the `0.5.5` version passed review only because
  the tests injected the environment variable by hand, and `0.5.6` carried the same gap forward.
  The suite now drives the gate through real settings files on a scoped `HOME`: unconfigured (no
  file, and a file with no `pluginConfigs`), user `false` and user `true`, a `false` under a
  different marketplace suffix (the prefix match), another plugin's identically-named option and a
  prefix-colliding plugin name, malformed JSON and a missing `jq` (both fail open), and managed
  `false` over user `true` *and* managed `true` over user `false` — the mirror case is what
  distinguishes real precedence from an or-of-falses. Every case also asserts that the wrapped
  statusline's stdout is unchanged, because a gate that blanked the status line would be worse than
  the bug it closes; one unstubbed end-to-end case exercises the script exactly as `settings.json`
  invokes it.

  Managed settings live at fixed root-owned paths a test cannot write, so those cases source the
  wrapper and stub the path list. To make that possible the script gained a `main` function behind
  the `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` sourcing guard already used elsewhere in this
  repository, and its stdin read moved inside it; a direct invocation behaves exactly as before.

- **The plugin's own documentation still described the pre-`0.5.5` single-surface switch.** Both
  the manifest's option `description` (which is what `/plugin configure` shows) and the README's
  `## Configuration` section called `rate_limit_guard_enabled` the kill switch for the StopFailure
  hook alone, and the README additionally told operators that "disabling the statusline tee is the
  operator's edit" — true before `0.5.5` gated the tee's write on the same option, wrong since.
  Both now say the switch governs the hook **and** the tee's snapshot write, and the README states
  where each surface reads it from and that the tee's precedence is managed → user → environment,
  so an operator can tell why a managed value outranks the one they set themselves.

## [0.5.6]

### Fixed

- **The statusline tee's kill switch read a channel that never reaches it.** The previous
  release gated the tee on `CLAUDE_PLUGIN_OPTION_RATE_LIMIT_GUARD_ENABLED`, but Claude Code
  exports `CLAUDE_PLUGIN_OPTION_<KEY>` to **hook processes** only, and this script is invoked by
  absolute path from the user's `statusLine` setting. The variable was therefore always unset,
  the `:-true` fallback always won, and the gate was decorative -- it only appeared to work
  because the tests injected the variable by hand. The tee now reads
  `pluginConfigs.<plugin>@<marketplace>.options.rate_limit_guard_enabled` from the user's
  settings directly, the sanctioned route for a non-hook consumer. The `pluginConfigs` key is
  matched by prefix so a fork or private catalog works, and every failure path -- no settings
  file, no jq, malformed JSON -- still runs the tee.

## [0.5.5]

### Fixed

- **The statusline tee ignored `rate_limit_guard_enabled` and wrote on every render regardless.**
  `scripts/statusline-tee.sh` is invoked by absolute path from the user's `settings.json`
  `statusLine`, not by the plugin hook runner, so it was reached whatever the plugin's enablement
  said — it was the one code path in this plugin that kept running while the plugin was disabled,
  rewriting `~/.claude/rate-limit-guard/rate-limits.json` on the statusline's refresh cadence. It
  now consults the option before taking the snapshot.

  The gate uses the new `hook::is_enabled` predicate rather than `hook::check_enabled`. The tee is
  a **transparent wrapper** around the user's real statusline: `check_enabled` exits 0, which here
  would have suppressed the wrapped command's stdout and blanked the status line. Only the tee's
  own write is skipped; the passthrough is unconditional and byte-identical either way. If the
  shared library cannot be read the tee still runs, consistent with this script's existing rule
  that no tee outcome ever alters the wrapped statusline.

## [0.5.4]

### Fixed

- **A cited plugins-reference section had been renamed upstream.** `scripts/statusline-shim.sh`
  attributed the 14-day orphaned-cache-directory grace period to a section called "Plugin cache and
  file access". That section is now titled **"Plugin caching and file resolution"**, and the cache
  root it documents is `~/.claude/plugins/cache`. The behaviour cited is unchanged and still stated
  verbatim; only the section title a reader would search for had moved, which is exactly the kind of
  silent rot that makes a citation unfollowable. The comment now names the current title and records
  the former one so the rename is traceable.

### Changed

- **Upstream doc stamps re-verified against the live pages (2026-08-10).** Each dated claim below was re-checked against the complete raw markdown source of the page it cites (`https://code.claude.com/docs/en/<page>.md`), not a summarized fetch, and each was confirmed by a verbatim quote before its stamp was refreshed. No claim changed; only the verification dates moved.

  - `hooks/record-rate-limit-stop.sh` — `StopFailure` still carries `Can block?: No` with
    "Output and exit code are ignored", which is what makes the hook side-effect-only.
  - `scripts/statusline-shim.sh` — the 14-day orphaned-version-directory grace period, quoted
    verbatim from the plugins reference.
  - `reference/reader-contract.md` — `used_percentage` running 0 to 100, `resets_at` in Unix
    epoch seconds, and `rate_limits` appearing only for Claude.ai subscribers with each window
    independently absent (statusline reference).

## [0.5.3]

### Fixed

- **Shared `hook-utils.sh`: `hook::jq_fields` now REPORTS a NUL byte in a payload value
  (#2122).** 0.5.1 stopped a NUL from failing the helper's cardinality check, by stripping every
  NUL out of each value. That keeps the helper working, but stripping also silently rewrites the
  value — `--no-verify<NUL>x` arrives as `--no-verifyx` — so a caller that owns a block/allow
  verdict cannot tell a clean payload from one that carried a NUL, and matches against a token the
  payload never held contiguously. The fact is now reported in a new `HOOK_JQ_FIELDS_NUL` global,
  set on EVERY call including every failure path, so such a caller can fail closed on its own terms.
  It is computed from the values as the payload carried them, BEFORE the strip; strip first and the
  flag would read "0" on every payload. Values themselves are unchanged — still stripped, so a
  scanning caller still sees everything after the NUL. This plugin's own hooks do not consult the
  new global, so their behaviour is unchanged. Synced from `lib/hook-utils.sh`.

## [0.5.2]

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

## [0.5.1]

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

## [0.5.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.4.4]

### Added

- **Reader contract: an operable read cadence for the reactive-only detection records.** The
  contract told consumers to "react to the detection records" with no when and no recency bound —
  the one thing a lane agent cannot derive. It now specifies: read on entering reactive-only and
  again before each new work claim; the recency baseline starts at the consumer's own start time
  and advances with each resume attempt (per-consumer, in-memory, never persisted) — records newer
  than it are live signal, older ones are history that never justifies a new pause on its own. The
  two inlined floors in `prompts/loops/loop-lane-prompts.md` are updated in the same change.

## [0.4.3]

### Fixed

- **The shim no longer runs an uninstalled plugin's tee (#1849).** `claude plugin uninstall` does
  not delete the version directory: the plugins reference documents that updating or uninstalling
  marks the previous version directory orphaned and removes it automatically 14 days later, so the
  files — `scripts/statusline-tee.sh` included — stay on disk for that whole window. `resolve_tee()`
  matched on the glob and mtime alone, so a removed plugin kept teeing and kept writing snapshots
  with no signal to the operator. A candidate whose version directory carries the orphan marker is
  now skipped, so uninstalling stops the tee at the next statusline refresh. The marking is
  documented; the marker's on-disk spelling was measured (Claude Code 2.1.220, against a relocated
  `CLAUDE_CONFIG_DIR`) and the shim's header records both, along with the fallback: should upstream
  rename or drop the marker, resolution degrades to exactly what it does today — a stale tee, never
  a broken statusline. The undocumented `installed_plugins.json` the header previously rejected
  stays rejected. Port of the context-guard fix from #1787 / PR #1844; the two shims remain
  deliberately unregistered as a byte-identical cluster (plugin name and header prose differ).

  **Existing installs need one `apply`.** The statusline runs the durable copy at
  `~/.claude/rate-limit-guard/bin/statusline-shim.sh`, which a plugin update never overwrites, so
  an operator who ran `apply` before this release keeps running the old shim — and keeps selecting
  orphaned tees — until they re-run it. `setup check` previously reported any installed-vs-shipped
  difference as INFO on the premise that an older revision "still resolves the newest tee"; that
  premise is what this fix falsifies, so a copy below revision 3 is now a FAIL with the migration
  stated in the finding. Uninstalling first is the trap worth naming: the setup skill goes with the
  plugin while the stale shim stays behind, leaving no in-product path to the remediation.

## [0.4.2]

### Changed

- **`setup`'s shell-wrapped statusline step now verifies its escaping by running a command instead
  of asking for a mental round-trip.** The check is `printf '%s\n' '<escaped original command>'`,
  compared against the original. Its single-quoted argument reproduces exactly the quoting context
  the emitted `sh -c '<escaped>'` uses; a double-quoted wrapper would instead let the outer shell
  expand any `$(...)` or backticks in the operator's own command before the check ever ran. Applied
  in step with `context-guard`'s near-identical setup skill.

## [0.4.1]

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

## [0.4.0]

### Fixed

- **The statusline tee no longer leaks its atomic-write temp file when the harness cancels it
  (#1807).** Claude Code
  [cancels an in-flight statusline script](https://code.claude.com/docs/en/statusline) when a new
  update arrives while the previous one is still running, and a cancellation between the write and
  the rename left the temp file behind permanently — no failed `rm` was needed to explain it, the
  process simply never reached the reclaim line. The only reclaim paths were write-failure and
  retry-exhaustion. 61 orphans were found clustered in one busy 27-hour window, which is the shape
  the correlation predicts: the rename retry loop holds the file open longest exactly when the
  target is contended, which is also when the session is busy enough to trigger a cancelling update.

  Two mechanisms ship, because neither is sufficient alone. A trap reclaims on exit and on a
  catch-able signal; an age-filtered sweep of leftover siblings on the next refresh recovers what a
  SIGKILL, a crash, or power loss leaves, which no trap can. Reproduced with an `mv` shim that parks
  so the kill lands inside the window: **before**, SIGTERM and SIGKILL each leak one file;
  **after**, SIGTERM leaks none and a SIGKILL orphan is reclaimed by the next refresh.

  The sweep costs nothing on a clean directory — a shell glob decides whether to spawn anything at
  all, so a normal refresh runs no extra process on a path that already sits at two to four times
  the 300 ms debounce interval. Its one-minute age floor cannot race a concurrent session's live
  temp, whose write-to-rename window is sub-second and bounded by the 300 ms retry loop.

- **A session with no rate-limit windows no longer overwrites a snapshot that has them (#1807).**
  On a mixed-auth machine an API-key or enterprise session would land a snapshot with `rate_limits`
  absent and a **fresh** `captured_at`, so consumers never saw "stale" — they saw a current snapshot
  with no data and dropped to whole-guard reactive-only, on a machine where a window-bearing session
  had good data available. Each such landing could destroy up to the reader contract's full
  ten-minute staleness budget of usable proactive data.

  The tee now skips the write when this session has no `rate_limits` and the target already has
  them. Window-bearing is decided structurally (jq `has("rate_limits")`, on the payload and on the
  target) — never by substring, which a forwarded value merely containing the string
  `"rate_limits"` (e.g. a session name) would defeat and clobber real windows. The preservation
  decision is serialized with the rename through a `mkdir`-based writer lock (atomic everywhere
  this runs, including Git Bash where `flock` is unavailable; a lock left by a killed writer is
  stolen past the same one-minute age floor the temp sweep uses), because an unserialized
  check-then-write let a windowless writer pass its check, lose the CPU to a window-bearing
  writer's rename, and clobber the fresh windows anyway. On lock-acquisition failure the
  windowless writer skips its write and the window-bearing writer proceeds unlocked —
  last-writer-wins between window-bearing snapshots is the pre-existing contract. The orphan sweep
  runs before the preservation early-return, so a machine where only windowless sessions remain
  active still reclaims a killed session's temp file. A windowless session still writes when the
  target has no windows either, so a machine with no window-bearing session keeps an honest
  staleness signal rather than an empty directory.

### Changed

- **`reference/reader-contract.md` inventories the temp-file shape.** The directory listing named
  `stop-events.jsonl.lock` and explicitly told tooling sweeping the directory to expect it, while
  omitting the only litter actually found there. It now documents
  `.rate-limits.json.tmp.<pid>.<random>`, why it can outlive its writer, and that a cleanup tool
  should leave it alone — one may belong to a live concurrent session, and the tee reclaims them
  itself. The script header's atomicity comment says the same, rather than implying the rename is
  the only outcome.

## [0.3.8]

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

## [0.3.7]

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

## [0.3.6]

### Fixed

- **Shared `hook-utils.sh`: an in-project file spelled as a Windows 8.3 short name is no longer
  silently skipped by the shared membership guard (#1636).** `hook::physical_path` canonicalized
  with GNU realpath, which under Git Bash resolves symlinks but leaves 8.3 short names
  (`KYLESE~1`) unexpanded, so a short-form `file_path` failed the `CLAUDE_PROJECT_DIR` prefix
  comparison in `hook::read_file_path`. The lib now expands short names on Windows/MSYS hosts
  (new `hook::expand_8dot3`, via `cygpath -l`) before the comparison, and only when the expanded
  form actually differs; a genuinely out-of-project file is still skipped. 8.3 generation is a
  per-volume property (`fsutil 8dot3name query`), so the defect was live only for checkouts on a
  volume that generates short names. Synced from `lib/hook-utils.sh`; this plugin's own hooks do
  not consume the membership guard, so their behavior is unchanged.

## [0.3.5]

### Fixed

- **The tee's `account` forward-pass no longer promises a no-change upgrade path it cannot deliver
  (#1685).** Four surfaces claimed that the release adding an account identifier upgrades the tee
  file for free — the reader contract's tee-shape bullet and single-account gap invariant, the
  README's known-gap bullet ("the wrapper automatically adopts any future account-identifying field
  the schema grows"), and the tee script's own header comment. Each described the writer accurately
  and then drew a conclusion broader than it supports. The writer selects on the **top-level key
  name only** (`to_entries` over the root object), matching `account` as a **case-insensitive
  substring**; an unmatched key is dropped with no diagnostic, in a contract that fail-closes on
  every other unresolvable input. The promise therefore holds only when the new field's own
  top-level key name contains `account`: `user`, `identity`, `org`, `seat`, and an `account_uuid`
  buried inside a non-matching object all vanish silently. All four surfaces now scope the claim to
  that shape and say every other shape needs a writer change.
- **The reader contract now states that a forward-passed key carries its whole value.** A selected
  top-level key crosses complete, nested objects included (`account_info: {uuid, display_name}`), so
  the untrusted-value discipline is restated to cover an **object of arbitrary strings** rather than
  only a scalar — the parse-with-a-JSON-parser, never-interpolate rule applies to the whole subtree.
- `statusline-tee.sh`'s **behavior is unchanged**; only its header comment was corrected. Widening
  the filter is a design question owned by `TODO(#1218)`, not this correction.

## [0.3.4]

### Fixed

- **Reader contract: the capability-detection mode table no longer contradicts its own per-window
  prose (#1612).** The table collapsed "tee file absent, stale, missing `rate_limits`, or absurd
  values" into one whole-guard `unknown → reactive-only` row, while the prose four lines below scoped
  an absurd value to "that window". The table is the line consumers copied, so the stricter reading
  won in practice: a single garbage window dropped the entire guard to reactive-only even with a valid
  window sitting at or above the 90% pause threshold — the guard failed open in exactly the case where
  it still had trustworthy data to pause on. The table now carries a **Scope** column and splits that
  row: tee file absent, stale, or missing `rate_limits` stay whole-guard; an absurd `used_percentage`
  or `resets_at` makes only that window unknown; and a separate whole-guard row states that
  reactive-only is reached only when no window is plausible. The prose adds the operative consequence
  the contract had left implicit — keep applying the floor to every still-plausible window, one absurd
  window is no reason to ignore a valid window already at or above 90, and a trip on the only
  plausible window is still a trip. The operable floor's values are unchanged.

## [0.3.3]

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

## [0.3.2]

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
  telemetry/audit-only, so no hook block/allow behavior changes.

## [0.3.1]

### Fixed

- **Setup's headless reconfigure recipe no longer claims `-y` is CLI-required for a non-TTY
  `uninstall`.** Verified against the live CLI (2.1.220) and current docs: `-y` only skips
  `uninstall`'s `--prune` confirmation, and this recipe never passes `--prune` — so `-y` had no
  effect and is no longer part of the recipe (#1410).

## [0.3.0]

### Added

- `scripts/statusline-shim.sh` — the durable statusline wiring target. The operator wires the shim
  once; it resolves the newest installed `statusline-tee.sh` at run time (newest by mtime across
  marketplaces under the effective `${CLAUDE_CONFIG_DIR:-~/.claude}` config root, skipping
  transient `temp_*` cache clones), so plugin version bumps never require re-wiring. Transparent
  in every path: no tee installed degrades to running the wrapped statusline alone, and a
  wired-standalone shim prints one diagnostic line instead of leaving a blank bar.
  Pure Bash builtins — no subprocess on the statusline path. Black-box test harness with 31
  assertions, including the two-shim chaining case and a relocated `CLAUDE_CONFIG_DIR`.
- **`setup apply`** — the skill is no longer check-only. `apply` installs the shim (byte-identical
  copy to `~/.claude/rate-limit-guard/bin/statusline-shim.sh`, idempotent, inert until the operator
  wires it) and writes nothing else; `settings.json` stays the operator's to edit.

### Changed

- **Wiring is now the shim, not the tee** (breaking for the printed wiring only; existing wiring
  keeps working until the next update). `setup check` prints
  `bash ~/.claude/rate-limit-guard/bin/statusline-shim.sh …`, gained an installed-shim state check,
  and reclassifies a statusline wired to a version-pinned plugin-cache path as LEGACY wiring
  regardless of whether that file currently exists — the old state only flagged a missing file.
  Rationale: `${CLAUDE_PLUGIN_ROOT}` is version-pinned and the old version directory is pruned
  ~14 days after an update, so cache-path wiring stops teeing at the next bump and then breaks the
  operator's whole statusline (`bash <missing>` → 127).
- `setup check` prints the sibling-composition wiring when `context-guard` is also installed, and
  states the measured per-tee refresh cost (~0.6–0.9 s on Windows/Git Bash, spawn-bound).
- `setup check` **unwraps recognized guard shims before composing the wiring it prints**, so a
  statusline already wired through the sibling shim (or through this one) is not wrapped a
  second time. Re-wrapping produced a chain running one tee twice — a duplicated write and
  another 0.6–0.9 s on every refresh — whenever the plugins were configured in sequence or
  `check` was simply re-run.
- The **combined sibling wiring is gated on the sibling shim actually existing**. `context-guard`
  being installed is not enough: its shim is written by its own `setup apply`, and printing a
  command that names a missing file reintroduces the `bash <missing>` → 127 failure this whole
  change exists to remove. When the shim is absent the single-shim form is printed instead,
  with the sibling's `apply` named as the step that unlocks the combined form.
- **Uninstall guidance is now ordered**: unwrap `statusLine` FIRST, then remove
  `~/.claude/rate-limit-guard/`. The previous "either order" wording let an operator delete the shim
  while the wiring still named it, which is the 127 failure again — and the shim's own fallback
  cannot cover it, because the fallback lives in the deleted file.

## [0.2.1]

### Changed

- **Setup states the accurate reason it is check-only.** It claimed the check-only carve-out as
  scoped to plugins whose entire configuration is native `userConfig` — a premise this plugin does
  not meet, since its statusline wiring lives in the user's own `settings.json`. The conclusion was
  right and the justification was not. The Purpose now names the condition that actually holds: no
  writable owned artifact anywhere in the surface. Each of the three surfaces is enumerated with why
  setup cannot write it, and the machine files under `~/.claude/rate-limit-guard/` are called out as
  runtime-owned plugin data rather than a fourth, operator-editable surface — which is what
  distinguishes a plugin that must not invent an `apply` from one that owes a narrow one.
- **Setup documents the headless reconfiguration route beside the interactive one.** The kill
  switch's only route was `/plugin configure rate-limit-guard`, leaving a headless consumer with
  nothing; the obvious guess, re-running `claude plugin install --config`, silently no-ops on an
  installed plugin. The fresh-install-only behavior and the uninstall-then-reinstall route it forces
  are now stated where the reconfiguration guidance lives. The recipe passes `-s <scope>` on both
  halves and `-y` on the uninstall: both commands default to `-s user`, so an unscoped pair removes a
  separate user record while a project- or local-scoped install keeps loading, and a non-TTY
  uninstall requires the confirmation flag to run at all.
- **The reader contract no longer cites a repository-level document.** Its no-`experimental.monitors`
  note pointed at `docs/PLUGIN-PHILOSOPHY.md`, a path that does not exist in an installed plugin's
  cache — where this contract is read by sibling-plugin consumers, the citation resolves to nothing.
  The note now states the reason a reader needs (Monitors is experimental; this plugin takes no
  dependency on one until it stabilizes) without a pointer that cannot be followed.

## [0.2.0]

### Changed

- **The single-account-per-machine text is repointed at its owner.** This reader contract
  carried its own copy of the assumption while naming loop-lane §6 as its owner, so the copy would
  contradict §6 the moment §6 moved — which it now has: §6 reframes the assumption as a known gap.
  §6 owns the framing; what stays here cites it rather than asserting it independently. What is
  local to the guard stays local: the writer already
  forward-passes any top-level `account`-matching key, so an identity field costs no plugin change
  the release one appears. The account-identity design itself is `TODO(#1218)`.

## [0.1.0]

### Added

- **Statusline tee wrapper** (`scripts/statusline-tee.sh`): transparent passthrough around the
  user's statusline command that atomically tees `rate_limits`, `captured_at`, and every
  session-distinguishing stdin field to the fixed contract path
  `~/.claude/rate-limit-guard/rate-limits.json` (temp file + rename; Windows locked-target renames
  retried then skipped without ever affecting the statusline pipeline). Standalone minimal
  statusline when invoked with no wrapped command; visible notice instead of a silent skip when
  `jq` is absent.
- **StopFailure detection hook** (`hooks/record-rate-limit-stop.sh`, matcher `rate_limit`):
  side-effect-only, jq-free reactive fallback appending bounded JSONL detection records to
  `~/.claude/rate-limit-guard/stop-events.jsonl`. Kill switch via the `rate_limit_guard_enabled`
  `userConfig` boolean.
- **Reader contract** (`reference/reader-contract.md`): the operable floor consumers inline —
  fixed tee path, 90%-of-either-window pause threshold, tripped-window `resets_at` pause end
  (later `resets_at` only when both windows trip), 10-minute staleness rule with mandatory
  session-Monitor arming while paused, capability-detect fail-open (absent/absurd values →
  reactive-only), and drain-then-pause.
- **Check-only `setup` skill**: verifies `jq`, tee freshness (distinguishing "no statusline
  configured" from "wrapper missing" and from a cache path gone stale after a plugin update), and
  the hook kill switch; prints the exact `settings.json` statusline edit for the operator — the
  skill never mutates user settings.
