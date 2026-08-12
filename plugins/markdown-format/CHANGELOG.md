# Changelog

All notable changes to the `markdown-format` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.11.13]

### Changed

- **Synced `hook-utils.sh`:** write `emit_telemetry`'s `data` payload to a temp file instead of passing it via `--argjson`, so payloads above the Windows command-line cap are not dropped (#1595).

## [0.11.12]

### Changed

- **Synced `hook-utils.sh`:** peel sudo clustered short options for chdir resolution (#1811); widen the valueless-short peel set and keep `-h` value-taking.

## [0.11.11]

### Changed

- **Synced `hook-utils.sh`:** peel sudo clustered short options for chdir resolution (#1811).

## [0.11.10]

### Changed

- **Synced `hook-utils.sh`:** refuse sub-minimum `stdin_read_timeout` values (#1883).

## [0.11.9]

### Changed

- **Synced `hook-utils.sh`:** `hook::jq_fields` returns 2 when jq is present but cannot parse the payload (#2157).

## [0.11.8]

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

## [0.11.7]

### Fixed

- **Two no-git cases 0.11.1 left open: a file below the root with no `CLAUDE_PROJECT_DIR`, and the
  opt-in pre-check.** 0.11.1 resolved the root from `CLAUDE_PROJECT_DIR` when the git probe could not
  answer. That covers an anchored session, but not the configuration the fix is about: the
  working-tree membership scope is gated on `CLAUDE_PROJECT_DIR` being **unset**, and the no-git
  regression fixture runs unset — so a root read off that variable cannot serve it, and a nested
  `.md` on a git-less host with no harness anchor was still skipped silently. The opt-in
  **pre-check**, which runs before `jq` exists, still resolved its root the old way as well: with
  `git` and `jq` both absent, a nested file made it read a repository that had opted in as one that
  never did, swallowing the `jq` notice it was owed.

  The root is now resolved from the filesystem when git cannot answer, by the walk git's own
  discovery performs: upward from the edited file for a `.git` entry, accepted as a directory for an
  ordinary clone or as a **file** for a linked worktree or submodule
  ([gitrepository-layout](https://git-scm.com/docs/gitrepository-layout)). git's answer is returned
  untouched whenever git produced one, so a host that has git is unaffected. `CLAUDE_PROJECT_DIR`
  remains below that as the last resort, for a project that is no working tree at all — an unpacked
  archive, a vendored copy — and only ever as the walk's terminator, never to widen scope, so the
  fail-closed reasoning in `markdownlint_config_discoverable` is unchanged. When nothing resolves,
  the previous hint stands, which keeps 0.11.1's out-of-tree bound true.

- **An escaping symlink can no longer hand its out-of-tree target to `--fix` on a git-less host.**
  Resolving the root from the filesystem makes discovery SUCCEED where it previously failed, and
  success is what puts a file in front of `--fix` — so for an in-repository symlink whose target
  lives outside the tree, the repository's own config opened the gate and the linter followed the
  link and rewrote a file outside the repository. Without git this scope could not ask
  `in_git_working_tree` anything, so containment went unchecked entirely; a symlink is precisely the
  shape whose lexical parent (inside the repository) and physical parent (outside it) disagree.

  Containment is now decided from the filesystem when git cannot answer, instead of being skipped.
  The check runs only where the physical path differs from the lexical one — which for an ordinary
  file it never does — so a git-less repository lints exactly as before; an undecidable *git* verdict
  still lints, while an escape the filesystem can prove does not. Both operands are canonicalized
  through `cd … && pwd -P`, the spelling `markdownlint_config_discoverable` and `CONFIG_ROOT` already
  compare in: `hook::physical_path` resolves via `realpath`, which leaves `/tmp` as `/tmp` where
  `pwd -P` resolves it to the underlying directory, so comparing one against the other would be a
  spelling mismatch rather than a containment answer.

  The root-level form of the same escape was reachable before this release too — there the old
  resolution already returned the repository root, so discovery already succeeded — and is closed by
  the same check.

  This also retires the `"$REPO_ROOT" == "$(dirname "$FILE")"` guard, which was true only for a file
  at the repository root: it spawned a second `git rev-parse` there wherever the payload's path
  spelling matched git's own, and was false for every nested file, which is why 0.11.1's test file
  records that the guard's inertness could not be made behaviourally observable. There is no longer
  an untestable branch to observe.

## [0.11.6]

### Changed

- **Carries the shared hook library's new `hook::is_enabled` predicate.** `hook::check_enabled`
  exits the process when a plugin is gated off, which is correct for a hook but wrong for a
  caller that must keep running afterward. The resolution is now also available as a predicate
  that returns instead of exiting. No behaviour of this plugin changes; the version moves so
  consumers receive the updated library.

## [0.11.5]

### Changed

- **Upstream doc stamps re-verified against the live pages (2026-08-10).** Each dated claim below was re-checked against the complete raw markdown source of the page it cites (`https://code.claude.com/docs/en/<page>.md`), not a summarized fetch, and each was confirmed by a verbatim quote before its stamp was refreshed. No claim changed; only the verification dates moved.

  - `hooks/markdown-format.sh` — shell-form hook commands rejecting `${user_config.*}`
    substitution, and every option still being exported to hook processes as
    `CLAUDE_PLUGIN_OPTION_<KEY>` (plugins reference, "User configuration"). The quoted rationale
    sentence is unchanged word for word.

## [0.11.4]

### Fixed

- **Shared `hook-utils.sh`: `hook::jq_fields` now REPORTS a NUL byte in a payload value
  (#2122).** 0.11.2 stopped a NUL from failing the helper's cardinality check, by stripping every
  NUL out of each value. That keeps the helper working, but stripping also silently rewrites the
  value — `--no-verify<NUL>x` arrives as `--no-verifyx` — so a caller that owns a block/allow
  verdict cannot tell a clean payload from one that carried a NUL, and matches against a token the
  payload never held contiguously. The fact is now reported in a new `HOOK_JQ_FIELDS_NUL` global,
  set on EVERY call including every failure path, so such a caller can fail closed on its own terms.
  It is computed from the values as the payload carried them, BEFORE the strip; strip first and the
  flag would read "0" on every payload. Values themselves are unchanged — still stripped, so a
  scanning caller still sees everything after the NUL. This plugin's own hooks do not consult the
  new global, so their behaviour is unchanged. Synced from `lib/hook-utils.sh`.

## [0.11.3]

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

## [0.11.2]

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

## [0.11.1]

### Fixed

- **A host without `git` no longer looks like "this file is outside every repository".** The
  working-tree membership scope added in 0.6.3 (#1030) skips a `.md` edited while
  `CLAUDE_PROJECT_DIR` is unset and the file sits outside any git working tree. Its probe,
  `git rev-parse --show-toplevel`, fails identically when git is not installed at all — so on a
  POSIX host without git the hook skipped **every** Markdown edit, including files inside a
  repository that carries a markdownlint config, with `jq` and `markdownlint-cli2` both present.
  The skip was silent and repo-wide, and git has never been a documented prerequisite of this hook:
  the README "Requirements" section lists Bash, `jq` and `markdownlint-cli2`, the setup skill checks
  those, and `hook::repo_root` has always tolerated git being unavailable by falling back to the
  file's own directory.

  The membership skip is now gated on git being available, so an undecidable verdict lints rather
  than skips — the same direction the gitignore scope already documents for the same input ("no
  `git` on `PATH`, no working tree, `git check-ignore` erroring → the hook lints"). The scope itself
  is unchanged wherever git can answer: an out-of-tree scratch file is still skipped, an inherited
  `GIT_DIR`/`GIT_WORK_TREE` still cannot admit one, and the fail-closed symlink-escape check ahead
  of it is untouched. Exposure of the fail-open is bounded by the consumer opt-in gate rather than
  by this scope: without git, `hook::repo_root` falls back to the edited file's own directory, so
  config discovery searches that single directory — a scratch `/tmp/comment-body.md` still does not
  lint unless `/tmp` itself carries a markdownlint config.

- **A nested `.md` now reaches the repository's markdownlint config when `git` is absent.** Gating
  the membership skip was not sufficient on its own: config discovery walks UP from the edited file
  and stops at `hook::repo_root`, which without git returns the hint it was given — the file's own
  directory. Root and start were therefore the same directory, the walk terminated immediately, and
  a repository whose markdownlint config sits at its root stopped linting everything below the root.
  That is the ordinary docs layout, so the case the membership gate was meant to restore stayed
  broken for most files in it.

  `CLAUDE_PROJECT_DIR` answers the same question without git, so it is now preferred as the walk's
  terminator when the git probe cannot resolve a working-tree top. It is used ONLY as the
  terminator, never to widen scope — discovery still starts at the file and still stops at a root —
  so the fail-closed reasoning in `markdownlint_config_discoverable` is unchanged. The capability is
  probed by running `git rev-parse --show-toplevel` rather than by testing `command -v git`, which
  answers yes for a shell function, a PATH stub, or a real binary standing in a directory that is no
  repository — every case where the fallback still applies.

## [0.11.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.10.1]

### Changed

- **Conduct-coaching prose trimmed from the hook's injected reports (#2021, remediation line 3).**
  The hook-surface classification pass marked markdown-format a hybrid whose only ablatable surface
  is the behavioral coaching text riding on its reports. Two strings are trimmed: the delta-gate
  repeat line drops its "a rule firing in bulk is configured away once in this repository's
  markdownlint config" lecture (now just the fact — unchanged from the previous run, detail
  omitted), and the truncation hint shrinks to a terse `(cap: markdown_format_max_findings)`
  pointer instead of instructing what to raise or configure. Everything policy-class is untouched:
  the deterministic `--fix` transform, the markdownlint finding relay (counts, rule histogram,
  per-finding lines), the rewrite disclosure on both channels, and the fail-closed code-execution
  trust gate on `.cjs`/`.mjs` configuration.

## [0.10.0]

### Added

- **A gitignored file is neither rewritten nor reported on.** The 0.9.0 config gate (#1809)
  spared repositories that carry no markdownlint config, but a repository that HAS
  one still had its gitignored scratch tier formatted and linted on every edit — one reported
  session took ~35,000 characters of MD013 findings on `.work/**` working notes that are deleted
  at the end of the task and never reviewed. The hook now asks `git check-ignore` and skips such
  a file before invoking `markdownlint-cli2`, so the rewrite and the report both stop. That is
  git's full exclude machinery, not `.gitignore` alone: every `.gitignore` up to the repository
  root, `$GIT_DIR/info/exclude`, and the user's global `core.excludesFile`. Same doctrine as
  `bash-format`'s `--apply-ignore` work
  (#1817): the consumer's existing declarative scope statement is honored on the hook's
  direct-file invocation rather than a plugin-specific ignore-glob key being invented. The
  mechanism differs because the tools do — `shfmt` needs a flag to apply `.editorconfig`
  `ignore = true` to a named file, whereas `markdownlint-cli2` needs no flag and instead has no
  ignore vocabulary at all in six of its ten discoverable config names (the rule-only
  `.markdownlint.*` family), which is exactly the case that stayed broken.

  A **tracked** file is never treated as ignored, even when a pattern matches it: `git
  check-ignore` consults the index, and a file under version control is part of the reviewable
  artifact whatever the patterns say. The question is asked from the file's **own directory**
  with a bare `./name` — on Windows Git Bash an absolute path can arrive in POSIX-mount form that
  `git.exe` rejects with exit 128, and reading that as "not ignored" would have left the reported
  platform broken while Linux CI passed; a relative name has no drive letter to translate.
  Resolving it that way also costs no path normalization, so the check adds one process to a
  Markdown edit rather than the three a `cygpath`-normalized repo-root prefix strip would have
  (the existing telemetry spawn-budget tests hold that line). Git's repository-selection and
  discovery environment is cleared for the check, as `in_git_working_tree` already does: an
  inherited `GIT_DIR` from a session wrapper would let the PARENT repository answer, and a
  session inside a linked worktree under an ignored path (`.claude/worktrees/**`) would then read
  every file it edits as ignored.

  The check **fails toward linting**: git absent, the path outside the working tree, or
  `check-ignore` erroring leaves the run alone rather than skipping it. A scope check that fails
  closed disables the hook invisibly and repo-wide, with no output to notice it by.

- **`markdown_format_lint_gitignored` (boolean, default `false`)** — set `true` to lint
  gitignored files anyway. Read from the `CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_LINT_GITIGNORED`
  hook-process mirror, since shell-form hook commands reject `${user_config.*}` substitution
  (Plugins reference, "User configuration", https://code.claude.com/docs/en/plugins-reference,
  fetched 2026-08-08); a value that is not `true`/`false` falls back to the default and is never
  interpolated.

### Changed

- README documents the path-scope rule, its opt-out, and `markdownlint-cli2`'s own
  `ignores`/`gitignore` keys as the finer-grained lever for tracked files;
  `/markdown-format:setup check` gained a path-scope step that reports the repository's ignored
  Markdown as out of scope and the effective opt-out value.

## [0.9.1]

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

## [0.9.0]

### Changed

- **The hook now runs only in repositories that carry a discoverable markdownlint config
  (#1809).** `markdownlint-cli2` ships a built-in default rule set, so an ungated run imposed a
  style the repository never chose — both `--fix` rewrites (observed falsifying a quoted changelog
  line via MD004 and destroying a line-leading issue reference via MD018) and default-rule findings
  (~115 unactionable MD013 findings per audit session on repos with no chosen line length). The run
  is now gated on one of the ten config file names markdownlint-cli2 documents as automatically
  discovered, anywhere between the edited file's directory and the repository root — the same
  opt-in doctrine as `bash-format`'s shfmt gate. No config → no run, no notice, no
  install-markdownlint nag. A `package.json` `markdownlint-cli2` property does not open the gate
  (markdownlint-cli2 reads it only under an explicit `--config` flag; its README "Configuration"
  section, fetched 2026-07-31). Part of #1809's single-writer decision: by default at most one
  in-place rewriter matches any file class, which dissolves the undefined-precedence race with
  `typos-format` this marketplace shipped for every Markdown edit.

## [0.8.6]

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

## [0.8.5]

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

## [0.8.4]

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
  `hook::physical_path` call sites — the unset-`CLAUDE_PROJECT_DIR` membership scoping and
  custom-rule path pinning — see the same expansion, and their fail-closed check for a
  canonicalization that returned its input unchanged is unaffected: the expansion runs only on
  the resolver's success path. Synced from `lib/hook-utils.sh`.

## [0.8.3]

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

## [0.8.2]

### Fixed

- **Carriage returns are normalized once at the source instead of twice at the
  end.** `0.8.1` stripped `CTX` and `SYSMSG` after they were composed, leaving
  `findings_raw` — which becomes `data.findings` — reading the raw linter output.
  A review called that a live leak on the telemetry channel; on Windows it is
  not, and the behavior turns out to be platform-specific. That array is built by
  piping into `jq -R`, and against a Windows jq build the carriage returns are
  already gone by the time jq emits. That is not established for the Linux jq
  this repository's CI runs, which has no text/binary mode distinction — there
  the normalization may be exactly what keeps the array clean. Which is the
  argument for normalizing at the source rather than downstream: a payload should
  not depend on which platform's stdio implementation is reading it, and one
  strip replaces four that would each have to be remembered when a fifth consumer
  appears. One consequence worth naming: the delta digest is hashed over
  `findings_raw`, so every digest recorded before this version invalidates once
  and produces one extra full-detail report per file. Self-correcting, and not a
  regression.
- **The carriage-return test could not fail — twice, for two different reasons.**
  It grepped the report for `\r` while the stub that produced that report emitted
  plain LF, so it passed identically whether the stripping code existed or was
  reverted. A test that asserts a behavior and cannot fail is worse than no test:
  it reads as coverage. The stub now emits real CRLF under `STUB_CRLF`. The
  first rewrite of the assertion was **still** vacuous on three of its four
  channels: on Git Bash, reading a value back through `printf | jq -r | $(…)`
  normalizes CRLF pairs away, and every CR here sits at end of line — so a
  decoded-value check structurally cannot see them. Only the fix-count line,
  whose CR is mid-string, was visible. The assertion now inspects the
  two-character `\r` escape in the raw emitted document instead, which is the
  bytes the hook actually produces. Both rewrites were confirmed by
  revert-probe rather than by reasoning.
- **The `+N more rule(s)` suffix had no positive test.** Only the negative case
  existed, and the stub could emit at most two distinct rule codes, so the
  overflow path this feature was named for was structurally unreachable from the
  suite. The stub now spreads findings across a configurable number of rule
  codes, and the suffix is asserted with its count alongside the unchanged
  top-five histogram.

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
