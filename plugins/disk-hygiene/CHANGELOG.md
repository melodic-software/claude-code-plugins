# Changelog

All notable changes to the `disk-hygiene` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.20.13]

### Changed

- **Single, early-terminating read of the engine per hook launch (issue 2853).** The always-on
  `Bash|PowerShell` launcher used to run two separate full-file `sed` passes over the ~3,500-line
  engine — neither stopping at the match — to recover `MIN_PYTHON` from near the top of the file. It
  now runs one `sed` whose address-block `q` terminates the read at the `MIN_PYTHON` line.
  `hygiene.MIN_PYTHON` remains the floor's single origin (PR 1028), and `test_hygiene.py`'s
  `VersionFloorTests` shape/count lock still passes; `hooks/run-python-hook.test.sh` now asserts
  behaviorally (via a recording `sed` shim plus an argv replay against a two-floor fixture) that a
  launch reads the engine exactly once and that the read stops at the first match instead of
  scanning to EOF.
- **README states the hook's measured always-on share (issue 2853).** The trust-surface record's
  launch-count sentence is replaced with a measured figure per the hook-budget convention's method
  (2026-08-16, Windows 11 + Git Bash, 32 runs per variant): ≈ 190 ms per shell tool call for the
  engine-gate hook, of which the engine read accounts for ≈ 24 ms (≈ 13%) in the single-read form,
  down from ≈ 38 ms (≈ 19%) in the two-pass form. `hooks.json`'s `"timeout": 60` is unchanged.

## [0.20.12]

### Changed

- Behavior-preserving simplifications from the repository-wide batch-simplify pass:
  duplicated helpers folded, dead code and redundant constructs removed, no functional
  change. Every group was verified by a fresh-context verifier agent against the
  plugin's own test suite.

## [0.20.11]

### Fixed

- **Flag the ordinary send-an-item-to-the-Recycle-Bin spelling (#2850).** The `Shell.Application`
  rule shipped for #2595 required the literal bin folder id — `NameSpace(10)` / `NameSpace(0xa)` —
  so `$sh.NameSpace('<parent folder>').ParseName('victim').InvokeVerb('delete')`, which addresses
  the item through its parent folder and never names the bin, returned no verdict and raised no
  prompt. That shape is now keyed on the delete VERB rather than on the folder id, and returns
  `ask` (or `deny` in audit-only mode) like every other recognized deletion spelling. The suffixed
  `InvokeVerbEx` spelling is covered by the same token, which a word boundary closed after
  `InvokeVerb` had excluded.
- **What the rule deliberately still does not catch (#2850).** `MoveHere` into an ordinary
  (non-bin) folder is a MOVE, not a deletion, and keeps deferring; so do `CopyHere` into an
  ordinary folder, non-delete verbs such as `InvokeVerb('open')`, the omitted default verb, and an
  opaque verb argument (`InvokeVerb($verb)`). The delete-verb set is enumerated, not identity-checked — a COM shell verb
  is named by the item's own verb collection, so completeness is not implied — and the pattern set
  now says so. The test note claiming `Move-Item` is the catch-all for these COM spellings is
  corrected: `_POWERSHELL_MUTATION_WORDS` matches neither `MoveHere` nor `InvokeVerb`.

## [0.20.10]

### Fixed

- **Restore the last two files #2635 never got back (#2590).** #2635 changed seven files; the
  stale-base squash in #2639 deleted them, #2714 restored four and #2803 restored four, and the
  overlap left `README.md` and `skills/clean/evals/evals.json` unrestored on `main` — a partial
  recovery the silent-revert canary cannot detect, because the deleting commit is already a
  recorded incident. The README's overview, approval-contract bullet, and deletion-report
  paragraph lead with tidiness again, and eval 12
  (`empty-directories-remain-first-class-tidiness-findings`) is back alongside eval 1's
  provenance-first expectation.
- **Three of the restored surfaces are corrected rather than restored verbatim (#2590).** Eval 1's
  expectation is byte-identical to #2635; the other three are not, and each deviation is
  deliberate. (a) The README approval bullet: #2635's own hunk was malformed and would have
  re-introduced a duplicated, truncated bullet; the replacement follows `SKILL.md` §5, which is the
  authority on what the approval table names. (b) The README deletion-report paragraph keeps the
  locked / changed / protected / needs-elevation / unverified enumeration that #2635's wording
  would have collapsed to "skips". (c) Eval 12's prompt is retargeted through the documented
  `--root-children` selection: as #2635 wrote it the prompt scanned `C:\` directly, which the
  engine has always refused, so the eval's expected output was reachable only by bypassing the
  confirmation gate.

## [0.20.9]

### Fixed

- **Re-land the engine half of tidiness-first reporting (#2590).** #2635 shipped
  `empty_directory_count`, plan `provenance`/`risk` validation, and preview/apply
  tidiness fields; a later stale-base squash deleted the engine while #2714 restored
  only the skill prose. Snapshot, `validate_plan`, `preview`, and `apply` again keep
  zero-byte directories first-class and require provenance/risk on every candidate.

## [0.20.8]

### Fixed

- **Windows read-only Bash allowlist was inert — 0 commands accepted (#2774).** Two
  compounding defects: (A1) MSYS path reinterpretation ran *after* `Path.is_absolute()`,
  which is False for POSIX-style heads on Windows-native Python, so `/usr/bin/ls` never
  reached the Git-root mapping; (A2) `_readonly_supporting_basename` did not strip
  `.exe`/`.EXE`, so real Git-for-Windows binaries never matched the allowlist. Move the
  MSYS branch ahead of the absolute gate and strip Windows executable extensions.
- **Engine-gate hard-`allow` leak for allowlisted inspection commands (#2774).** In
  `--mode engine-gate`, an allowlisted command that also names the engine path emitted
  `permissionDecision: "allow"`, bypassing the user's prompt in every consumer session.
  Downgrade that path to `ask`; belt mode still hard-allows.
- **Exclude user-writable `%LOCALAPPDATA%\\Programs\\Git` from NT trust roots (#2774)**
  and reword the trust-root comments so they no longer claim independence from
  environment-derived input.

### Changed

- **CI:** add a focused `disk-hygiene-guard-windows` lane (`windows-2025`, GuardTests
  only) so NT trust/MSYS/basename branches cannot regress silently on Linux-only CI.

## [0.20.7]

### Fixed

- **Re-landed the belt's read-only allowlist and session-honest docstring, and anchored
  its trust check (#2618, #2691).** PR #2641 merged from a tree predating PR #2639 and its
  squash merge reverted #2639 wholesale; CI stayed green because the revert removed the
  tests with the code. `resolve_mode()` again documents that a skill-frontmatter
  `PreToolUse` hook stays armed for the rest of the session rather than only while cleanup
  is the active work, and the read-only supporting Bash allowlist (`ls`, `test`, `stat`,
  `du`, `pwd`, `basename`, `dirname`, `find`, `file`, `[`) is restored as absolute paths
  under trusted system directories — `find` gated by the full GNU/BSD side-effect primary
  set, everything else still deny-by-default.
- **Recycle Bin deletion spellings are recognized on the PowerShell belt (#2595).**
  `Microsoft.VisualBasic.FileIO.FileSystem::DeleteFile`/`DeleteDirectory` and
  `Shell.Application` `NameSpace(10)`/`NameSpace(0xa)` with `MoveHere`/`InvokeVerb` now
  prompt like `Remove-Item`. The skill's own manual-handoff lane recommends Recycle Bin
  removal, so these were the one deletion route the belt never saw.

### Security

- **Trusted-binary matching is anchored to a resolved installation root, not a path
  substring (#2618).** `_TRUSTED_READONLY_BIN_SUBSTRINGS_NT` matched fragments such as
  `/git/usr/bin/` and `/windows/system32/` anywhere in a path, so a repository-controlled
  `D:/anyrepo/git/usr/bin/find` was trusted and a planted binary carrying an allowlisted
  basename was hard-`allow`ed, bypassing even the user's own permission prompt. Trust now
  derives from independently located Git installation roots (`ProgramFiles`,
  `ProgramFiles(x86)`, `LocalAppData\\Programs`) and from `%SystemRoot%`, compared as an
  anchored case-insensitive path prefix — never from a `PATH`-selected `git.exe`.
- **`[` must clear the same executable-identity check as every other head (#2618).** The
  `[ ... ]` branch returned before the trusted-binary check, so `[` was trusted on name
  alone — the shell-function-shadowing exposure the guard itself cites to deny bare
  `python`/`python3`. It is now allowed only as an absolute trusted `/usr/bin/[ ... ]`
  form.
- **Bare allowlisted heads are denied (#2618).** `shutil.which("ls")` finds the system
  binary while Bash still executes an exported `BASH_FUNC_ls%%` first; only absolute
  paths under trusted system directories (MSYS `/usr/bin/...` mapped through the known
  Git root on Windows) can hard-`allow`.

## [0.20.6]

### Fixed

- **Re-landed tidiness-first reporting and corrected the belt's documented posture (#2590,
  #2618).** PR #2639 and then #2641 squash-merged from stale bases and silently reverted the
  prior markdown fixes (#2691). Reports are again ordered by tier and evidence strength — never
  by byte size — with empty directories as first-class findings; `provenance` and `risk` return
  to the plan schema; preview and apply lead with tidiness. The skill and safety-model docs now
  state that skill-frontmatter `PreToolUse` hooks stay armed for the rest of the session, drop
  the false exec-form claim (shell form since 0.17.9 / #2568), name the long-path Recycle Bin
  hard-stop, declare relocation out of scope, and thin Gotchas harness duplication into
  `safety-model.md` pointers. Guard-code recovery remains in the sibling lane.

## [0.20.5]

### Fixed

- **PowerShell `>>` append redirection is flagged like `>` (#2675).** `_POWERSHELL_OUTPUT_REDIRECT`
  matched neither character of a `>>` pair — `(?![=>&])` rejects the first `>`, and the lookbehind
  rejects the second — so `<cmd> >> append.txt` wrote a file with no prompt while the same command
  with `>` prompted. Append is matched explicitly (`>>`, `2>>`, `*>>`) without widening that
  lookahead (load-bearing for the stream-merge exclusion from #2627 and the `$null`-discard
  exclusion from #2671). `>> $null` stays silent — a discard, not a file write — and requires a
  real token terminator after `$null` so punctuation continuations like `>>$null/out.txt` stay
  flagged.

## [0.20.4]

### Fixed

- **PowerShell `$null` discards (`2>$null`, `*>$null`, `>$null`) are no longer flagged as
  file-overwriting redirection (#2615).** The stream-merge exclusion released in 0.17.11
  closed only the `>&` form; the character after `>` in a discard is `$`, so every
  `2>$null` — PowerShell's `/dev/null`, the standard way to silence a noisy read-only
  command — kept prompting. `_POWERSHELL_OUTPUT_REDIRECT` now also excludes a `>` whose
  target is `$null`, spelled as guardrails' `ps::write_bypass` spells the same exclusion
  and matched case-insensitively (PowerShell variable names are). Only horizontal
  whitespace is skipped between `>` and `$null`, and `$null` itself must be followed by a
  real token terminator (whitespace, `;`, `|`, `)`, `}`, or end-of-string) — so punctuation
  continuations like `>$null/out.txt` or `2>$null\evil.ps1` stay flagged as file writes.
  Real redirection still prompts: `2>out.txt`, `> out.txt`, `1>file`, `'data' > file`, a
  non-`$null` variable target (`2>$nullish`), and a command that discards one stream while
  redirecting another (`... 2>$null > out.txt`).

## [0.20.3]

### Fixed

- **The documented argument surface names the root-children flags again (#2588).** Resolving the
  conflict in #2641 inserted a fresh "Arguments and boundaries" opening paragraph above the existing
  one instead of merging into it, orphaning that paragraph's continuation. The section was left with
  two overlapping sentences, and the authoritative first one silently dropped `--root-children` and
  `--root-child <name>` — reintroducing exactly the wrong-argument-surface defect #2589 was filed
  for, against the feature #2636 had just shipped. The two sentences are merged back into one
  carrying every flag, and the skill's `argument-hint` now lists the root-children flags it had
  never carried. Documentation only: the engine has accepted both flags since #2636 and its
  behavior is unchanged.

## [0.20.1]

### Fixed

- **Empty directories at `--max-depth` are inventoried as size 0 (#2618).** A depth cut used to
  mark every boundary directory truncated even when it had no children. One first-child probe
  (no recursion, fail-closed on unreadable) now records empty boundaries as walked with size 0
  and keeps them out of the truncated set; directories with children and unreadable directories keep
  the previous not-walked marking. VCS and protection cuts are unchanged — emptiness does not
  answer those refusals.

## [0.20.0]

### Added

- **A strictly evidence-gated manual path for provably redundant standalone Git checkouts
  (#2596).** `handoff-verify` accepts an optional `--vcs-evidence` file and remains read-only.
  Without that option, and in preview/apply unconditionally, VCS metadata and tracked content stay
  categorically protected. With it, the verifier relaxes only the Git-specific blockers and `.git`
  scan boundary after all four gates pass live: porcelain status is empty (including untracked,
  gitignored-but-present, and submodule dirtiness via `--ignored=matching`); every local branch tip
  plus a detached `HEAD` is confirmed by exact SHA through `gh api` against the checkout's
  configured `github.com` remote; every stash SHA appears in an independent declared checkout's
  stash list (or there are no stashes); and the checkout is bound to the existing exact-path
  operator-approval file. The live `.git` repository set must exactly match the evidence map, every
  common Git directory must remain inside the approved checkout (rejecting linked worktrees), and
  stash copies must sit outside every approved deletion path with a `--git-common-dir` distinct from
  the candidate's Git store (so a linked worktree of the same repository cannot count as a backup).
  Any missing tool, unsupported provider, dirty tree, unconfirmed head, unmatched stash,
  malformed output, timeout, or set/boundary mismatch retains the categorical reasons and returns
  `contested`; every non-Git protection remains untouched. The Bash guard admits only the exact
  read-only `--vcs-evidence <file>` handoff shape.

## [0.19.1]

### Fixed

- **Read-only supporting Bash allowlist verifies executable identity (#2591).** Bare
  names (`ls`, `find`, …) are allowed only when `shutil.which` resolves into a trusted
  system directory (`/bin`, `/usr/bin`, and siblings; Windows System32 / Git usr\bin
  when applicable). Absolute paths under those directories are allowed; relative
  path-qualified forms and PATH-shadowed binaries outside trusted prefixes fail closed
  (same rationale as denying bare `python`/`python3`). Symlinks are realpath'd so a
  trusted-prefix link into an untrusted tree is denied.

## [0.19.0]

### Fixed

- **Empty-directory counting is linear in inventory size (#2590).** Snapshot finalization
  precomputes parent paths once instead of scanning the full inventory per directory, so the
  tidiness metric stays tractable near the 250,000-entry limit.
- **Scan-error directories are not counted as empty (#2590).** When `os.scandir` fails, the
  directory is recorded as not-walked (unknown) and excluded from `empty_directory_count`, so a
  coverage gap is not reported as empty residue.

### Changed

- **Reporting is tidiness-first; reclaimable bytes are secondary (#2590).** Skill guidance,
  scan/preview/apply report fields, and the approval table now lead with provenance, what an
  entry is, why it is removable, and risk. Empty directories stay first-class and rankable via
  snapshot `empty_directory_count`, preview `empty_directory` / `empty_directories`, and apply
  `paths_removed` / `empty_directories_removed`. Byte totals remain available but no longer
  frame the run. Plan candidates require `provenance` and `risk` alongside the existing
  evidence fields.

## [0.18.0]

### Added

- **Root-children mode for OS-managed volume roots (#2588).** Targeting `C:\` or `/` without a new
  flag still fails closed — nothing walks an OS-managed root as a whole. With `--root-children` the
  engine enumerates that root's immediate entries only, hard-excludes OS-owned / hidden / system /
  reparse / mount / protected-shell-folder / non-directory names (preferring more exclusions when
  ambiguous), and returns `root-children-selection-required` until the operator names one or more
  admitted directories via repeatable `--root-child <name>`. Selected children are audited into one
  snapshot and one report; the volume root's own files and every skipped entry are never inventoried.
  Documented in `skills/clean/SKILL.md` Arguments, the confirmation gate, the scan template, and
  `reference/safety-model.md`. The skill-scoped guard accepts the new scan flags.

### Fixed

- **Linux OS-provisioned root directories are excluded from root-children admission (#2588).** The
  Linux allowlist now matches the Windows/macOS posture for conventional OS roots (`home`, `root`,
  `tmp`, `opt`, `srv`, `media`, `mnt`, and the existing `bin`/`boot`/… set), so `/tmp` and `/home`
  are not reported as admitted audit targets.
- **Root-child selection preserves exact basenames on case-sensitive hosts (#2588).** On Linux,
  `--root-child Cache` resolves only to `Cache`, not a case-folded sibling such as `cache`, and the
  scan filter keeps that exact name. Windows and macOS remain case-insensitive.

## [0.17.11]

### Fixed

- **PowerShell stream merges (`2>&1`, `*>&1`) are no longer flagged as file-overwriting
  redirection (#2615).** `_POWERSHELL_OUTPUT_REDIRECT` matched the `>` inside `2>&1` because
  its lookaround only excluded adjacent `<`, `>`, and `=`. In PowerShell `>&` is only ever a
  stream merge and never designates a file, so ordinary diagnostic commands that capture
  combined output were prompting as mutations — approval-fatigue noise that blunts real
  deletion prompts, especially once the belt stays armed for the rest of the session (#2591).
  The detector now also excludes a following `&`; `2>out.txt` and `'data' > file` still
  prompt.

## [0.17.10]

### Fixed

- **Document the real clean-skill argument surface (#2589).** The Arguments
  section omitted `--max-depth` and `--confirmed-large-scan` (and related
  flags the engine accepts), which undercut the bounded-first large-target
  workflow the skill body requires.

## [0.17.9]

### Fixed

- **The skill-scoped guard launches in shell form too, closing the last exec-form instance
  (#2568).** `skills/clean/SKILL.md`'s frontmatter belt was the third and final registration left
  on exec form after #1416 — `"command": "python3"` plus `args`, unchanged since #215 and so
  predating `hooks/run-python-hook.sh` entirely. Exec form is a bare `PATH` lookup, and on stock
  Windows `python3` resolves to the zero-length `WindowsApps\python3.exe` App Execution Alias
  stub, which is not a real executable: the belt could not launch there at all, and a failed hook
  launch is non-blocking, so it silently enforced nothing. Unlike the wired hooks this instance
  was **latent, not dead** — it works wherever `python3` is a real interpreter — so the
  conversion was held to argv equivalence rather than merely to launching: the vector
  `destructive_guard.py` receives is byte-identical before and after, verified against roots
  containing spaces and backslashes, with only argv[0] changing from the interpreter name to the
  launcher path. The command string substitutes **only** `${CLAUDE_PLUGIN_ROOT}`, the sole token
  Claude Code provides to a skill-frontmatter hook; `--authorized-data-root`
  `${CLAUDE_PLUGIN_DATA}` is deliberately **not** reintroduced, because that token is unavailable
  on this surface and causes launch refusal (#1014). Residual, unchanged: the launcher exits 0
  silently in guard mode when no interpreter resolves anywhere on its ladder, so this closes
  "cannot start against the alias stub", not "fails closed with no Python".
- **The skill-hook tests no longer encode the launch form they were meant to check.** Three tests
  in `skills/clean/scripts/test_hygiene.py` read the frontmatter form-specifically — one required
  an `args:` line (and would have raised on shell form), one hand-stripped quotes off the
  `command:` line, and one asserted the literal `python3` as the interpreter. That is the same
  bug-as-contract shape that let the wired guard ship dead twice. The frontmatter is now read into
  a hook mapping and fed to the existing form-agnostic `_hook_argv()` helper, so both surfaces are
  asserted through one path; the interpreter test now exercises `run-python-hook.sh`'s real
  resolution ladder instead of restating it. Two tests were added: one asserting the four
  portability properties for this surface (launcher named in `command`, no `args`, `shell: bash`,
  every placeholder double-quoted) — verified to **fail** against the pre-change frontmatter — and
  one asserting the argv equivalence above.
- **Docs that described this hook's form are corrected.** `README.md`, `skills/setup/SKILL.md`,
  `skills/clean/reference/safety-model.md`, `hooks/run-python-hook.sh`'s header, and the
  `python3_alias_probe.py` docstring and operator message all stated that the belt launches as the
  literal `python3`, several of them as the rationale for a check. The reason is now grounded on
  the launcher rather than on a hook form that no longer exists.

### Changed

- **`/disk-hygiene:setup check` verdicts the interpreter LADDER, not `python3` alone.** Direct
  fallout of the conversion above: while the belt named `python3` in exec form, a stubbed first
  rung genuinely was a guard-launch failure, so step 2 mapped `store-alias-stub` straight to FAIL.
  Now that every surface routes through `hooks/run-python-hook.sh`, that mapping reports a healthy
  install as broken — a host with real Python installed without "Add to PATH" but with the `py`
  launcher has a stubbed `python3`, a working `py -3`, and a guard that launches on every call, yet
  would have been told to reinstall Python. Step 2 now treats the alias probe as **diagnostic
  input**, resolves the ladder in the launcher's own order (skipping stubs), and checks the
  selected interpreter against the parsed `MIN_PYTHON`. FAIL is unchanged in substance where it
  matters — an **exhausted** ladder or a below-floor interpreter, both still FAIL under a disabled
  toggle — and a stubbed `python3` beside a working `python`/`py -3` becomes a **WARN** naming the
  real residual: a bare `python3` typed by hand still opens the Microsoft Store. The probe's own
  return values are unchanged; only the mapping to a verdict and the message wording moved.

## [0.17.8]

### Fixed

- **Wired hooks launch in shell form, restoring the destructive guard on Windows (#1416).**
  `0.17.6` moved both `hooks/hooks.json` registrations onto `"command": "bash"` + `args` to
  resolve a real Python 3 interpreter (#1504) — and in doing so reintroduced the exact launch
  failure #1006 had already fixed for the skill-frontmatter hook. Exec form (`args` present) is
  a bare `PATH` lookup, and on Windows `bash` resolves to the WSL relay `System32\bash.exe`
  before Git Bash: `execvpe(/bin/bash) failed: No such file or directory`. A hook that fails to
  launch is a **non-blocking** error, so `destructive_guard.py` never ran and the PreToolUse
  gate silently enforced nothing on every such host. Both registrations now name
  `run-python-hook.sh` directly with `"shell": "bash"` and no `args`, which Claude Code routes
  through Git Bash instead of a `PATH` lookup. Every `${CLAUDE_PLUGIN_ROOT}` /
  `${CLAUDE_PLUGIN_DATA}` placeholder is double-quoted, so the argv is byte-identical to the
  exec-form vector across paths containing spaces. The #1504 Python-resolution behaviour is
  unchanged — only the launch mechanism moves. `hooks/run-python-hook.test.sh` previously
  asserted `.command == "bash"`, encoding the defect as the contract; it now asserts the
  portability property (launcher named in `command`, no `args`, `shell: bash`, every
  placeholder quoted).
- **Security records now assess the shell-form launch instead of asserting the old exec form.**
  The README trust-surface record and `skills/clean/reference/safety-model.md` still bounded the
  plugin-level hook by "exec form (no shell)" — a safety claim the same change disproved, so the
  plugin's own security assessment reasoned from a false premise. Both now state what shell form
  does and does not guarantee: the command string is a fixed literal in the plugin's own
  `hooks.json` with no model-, repo-, or session-supplied interpolation, whose only substituted
  values are Claude Code's own double-quoted `${CLAUDE_PLUGIN_ROOT}`/`${CLAUDE_PLUGIN_DATA}`
  placeholders — verified byte-identical to the exec-form argv for roots containing spaces and
  backslashes — while noting that those placeholders are substituted textually before bash parses
  the result, so the quoting bounds whitespace and backslashes rather than every shell
  metacharacter. The invariant is now maintained by `hooks/run-python-hook.test.sh` and the
  form-agnostic `test_hygiene.py` hook helpers rather than being structural (repo-wide gate: #2569).
  `skills/clean/SKILL.md` split its single launch bullet per surface — the wired gate resolves
  Python through `run-python-hook.sh`, while the skill-scoped belt is the one still exec-form on a
  bare `python3` (#2568) — and `safety-model.md` dropped a stale claim that the `Stop` detector
  shares the guard's `python3` lookup and leaves that vector unreported, which #1504 already closed.

## [0.17.7]

### Changed

- **Docs:** actionable `/plugin configure` guidance now uses the marketplace-qualified form
  (`<plugin>@<marketplace>`; generated option blocks use `@<marketplace>`) per
  [`docs/extensibility-contract-smoke-tests.md`](../../docs/extensibility-contract-smoke-tests.md)
  Test E (#1360). Targetless references to the flow stay unqualified.

## [0.17.6]

### Fixed

- **Wired hooks launch through a bash Python resolver (#1504).** Both `hooks/hooks.json`
  registrations now invoke `hooks/run-python-hook.sh`, which resolves a real Python 3
  interpreter (rejecting the zero-length WindowsApps `python3` alias stub) before exec'ing
  the guard or the Stop detector. When no interpreter resolves, the guard still fails open
  (exit 0) and the detector emits a `systemMessage` on stdout — so the blind spot the
  detector exists to surface is visible even when bare `python3` cannot run.

## [0.17.5]

### Added

- **HOOK_TELEMETRY_SINK envelopes on both wired hooks (#1505).** The fleet's first
  native Python telemetry emitter (`lib/hook_telemetry.py`) mirrors
  `hook::emit_telemetry` for the stdlib-only `destructive_guard.py` PreToolUse guard
  and the `guard_launch_monitor.py` Stop detector. Meaningful outcomes emit
  `ok` / `blocked` / `error`; pure inapplicability short-circuits stay silent.

## [0.17.4]

### Fixed

- **Guard-launch detector scans transcript head plus tail (#1514).** Guard failures that fall
  outside the 2 MB tail window are no longer lost when a later turn appends a large record.

## [0.17.3]

### Fixed

- **PowerShell guard now surfaces move/rename/overwrite spellings (#387).** `Move-Item`, `Rename-Item`,
  `Set-Content`, `Out-File`, `New-Item -Force`, output redirection, and `Format-Volume`/`Clear-Disk`
  join the existing deletion-spelling `ask` bar on the PowerShell lane.

## [0.17.2]

### Fixed

- **`_discard_stream` no longer re-closes the fd it just repaired.** When stderr's fd was closed
  outright, `os.open(os.devnull)` could return that same fd number; `dup2` was then a no-op and the
  unconditional `close(null_fd)` left fd 2 closed again, defeating the null-device redirect. The
  guard now skips closing `null_fd` when it is the target fd. Covered by a unit test that closes fd
  2 before calling `_discard_stream`.

## [0.17.1]

### Changed

- **Upstream doc stamps re-verified against the live pages (2026-08-10).** Each dated claim below was re-checked against the complete raw markdown source of the page it cites (`https://code.claude.com/docs/en/<page>.md`), not a summarized fetch, and each was confirmed by a verbatim quote before its stamp was refreshed. No claim changed; only the verification dates moved.

  - `skills/clean/scripts/destructive_guard.py` — the quoted hooks-reference sentence on exit code
    1 being a non-blocking error, and `exit 2` being the policy-enforcement code, is still present
    verbatim.

## [0.17.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.16.0]

> Version note: `0.14.0` is never published. This entry claimed it while open, and 0.15.0 shipped
> first with a note pointing here; taking the next free number on merge is what keeps both entries
> truthful about the order they actually landed in.

### Fixed

- **Byte accounting can say "unknown" and "not reclaimable local bytes" (#1806).** Finding 2 of
  the live audit: a truncated subtree emitted `logical_size: 0`, byte-identical to a genuinely empty
  directory, while hard-linked names each contributed their full `st_size` to every total. PR #1818
  landed the `size_qualifiers` / `file_attributes` mechanism for cloud placeholders and deliberately
  left aggregates alone so this change could own the rest.

  Every entry now records `nlink` and `allocated_size` (cheap `st_blocks * 512` on POSIX; null on
  Windows where that field is absent). A truncated directory — max-depth, protected name, or VCS
  boundary — carries `logical_size: null` and `not-walked` rather than pretending to be empty. Files
  with `st_nlink > 1` carry `hardlinked`; sparse files carry `sparse` when the platform exposes the
  signal. Snapshot, preview, apply, and the scan-complete summary each report
  `reclaimable_local_bytes` (or `target_reclaimable_local_bytes` /
  `reclaimable_local_bytes_removed`) as a figure distinct from the walked logical roll-up: every
  qualified entry is excluded, so a report can no longer honestly claim gigabytes removed when the
  observed free-space delta is ~0 because the bytes were shared, remote, or never inventoried.

### Follow-ups left open on #1806

Findings 3 (a `summarize` surface), 4 (Stop-detector marker amortisation), 6 (probe path
provenance vs the guard's trusted settings channel), and 7 (run-state retention / snapshot path
containment) stay out of this PR — each needs a design or coupled-grammar call rather than a
mechanical completion of the byte-qualification vertical slice. Findings 1 and 5 already shipped in
0.13.0.

## [0.15.0]

### Fixed

- **A confirmation question is unanswerable when its acceptance bar names something the question
  never showed.** The gate applied one bar — "an affirmative answer naming exactly the tier and path
  list just shown" — to every question the skill asks, including the no-target prompt and §1's
  large-scan confirmation. Neither has presented a tier or a path list, so no reply a human could
  give satisfied the stated bar, and the two questions the gate exists to protect were the only ones
  it could actually be cleared for. The question surface rule and the answer floor (the user's own
  answer, this session, never inferred, stop on rejection) stay common to all four questions; what an
  answer must *name* is now stated per question — a directory for target selection, the target plus a
  deliberate unbounded walk for scan scope, the exact tier and path list for removal and the manual
  handoff. §1's and §6's cross-references now name their row instead of asserting the deletion bar
  applies unchanged, and the gate states the obligation that generated the defect: ask each question
  so it shows what its row requires the answer to name.

- **The confirmation gate fell back to an inline question only when `AskUserQuestion` was
  *absent*.** Permission mode `dontAsk` "auto-denies tools unless pre-approved … `AskUserQuestion` …
  denied even if you've allowed them"
  ([permissions](https://code.claude.com/docs/en/permissions), fetched 2026-08-08), which leaves the
  tool visible in the pool while every call fails; only a bare-name deny rule "removes the tool from
  Claude's context entirely". Absence and denial are therefore distinct states, and keying the
  fallback on absence let a `dontAsk` session pick a tool it cannot use and leave the destructive
  confirmation gate unsatisfied rather than asking inline. The fallback now triggers on absent,
  denied, **or otherwise unusable** — including a denial discovered only by calling it — so a state
  neither named case anticipates still routes to the inline question.

- **The `python3` alias probe could not be reached on a machine whose only alternate interpreter
  cannot run it.** `setup` step 1(b) classifies the `python3` resolution with a bundled inspect-only
  probe launched through some other interpreter, and routed to the PowerShell equivalent only when no
  such interpreter existed at all. A real-but-incompatible launcher — Python 3.6, which the same
  section already names as an interpreter that rejects `from __future__ import annotations`, or a
  legacy `python` 2.x — is not absent, so the check had no path to a verdict and could classify
  neither the Store stub nor its own remediation. The PowerShell fallback now also covers a chosen
  interpreter that emits no verdict.

## [0.13.0]

> Version note: `0.11.0` is claimed by #1804 (PR #1818) and `0.12.0` by #1805 (PR #1819), both open
> against this manifest. This entry takes the next number so the three do not collide; merged in
> issue order the changelog reads contiguously.

### Fixed

- **Hint matching is case-insensitive, on every platform (#1806).** `has_protected_name()` casefolds
  and `matching_hints()` did not, so on Windows and macOS — where both spellings name the *same*
  file — protection was case-robust while discovery was not. Measured against the shipped baseline
  before the fix: `Thumbs.db`, `tmp-build`, and `scratch.md` each matched a hint while `thumbs.db`,
  `TMP-build`, and `Scratch.md` matched nothing.

  Every glob the engine evaluates now goes through one `glob_matches()` helper — hints, consumer
  protection globs, and the protection re-checks in the preview, verify, and apply lanes — so
  discovery and protection cannot disagree about what a name is. The protection-side globs move
  deliberately rather than by accident, and casefolding is the safe direction for both roles: a
  protection glob that matches more can only keep more, and a hint that matches more can only
  surface more for triage, since hints are discovery signals and never cleanup verdicts. The helper
  uses `fnmatchcase` on casefolded operands rather than `fnmatch`, whose folding follows the host
  platform — a matcher whose verdict changes with where the scan runs is not a matcher a protection
  can rest on.

- **Atomic-write staging remnants are hinted as a class, not as one producer's filename (#1806).**
  `*.tmp` requires `.tmp` as a *suffix* and `.claude.json.tmp.*` encodes one producer's exact
  prefix. Neither matches `.tmp` as an **infix** before a pid and random suffix — the standard
  write-temp-then-rename shape — while the producer-specific hint's own `reason` claimed to cover
  the class. A scan of one sibling plugin's state directory returned **`hinted_entries: 0` across 63
  entries**, 61 of which were remnants of exactly that shape; they surfaced only because a subagent
  read the directory positionally.

  A new `atomic-write-staging-remnant` hint (`*.tmp.*`, ceiling `medium`) covers the class.
  `.rate-limits.json.tmp.<pid>.<random>` and `settings.json.tmp.4` now hint where they previously
  matched nothing. The producer-specific hint still fires alongside it, since it carries a narrower
  reason and a class hint does not replace that.

- **The Bash denial text no longer under-reports the allow-list (#1806).** The documented bootstrap
  path is to submit a wrong shape so the denial teaches the grammar, and it enumerated four engine
  subcommands while omitting the read-only kill-switch probe that `_decide` allows before the
  classifier ever runs. A consumer learning the allow-list from the denial never learned the probe
  is permitted — and the probe is the step that lets the model state the kill-switch value honestly
  instead of assuming the default. The denial now also discloses the bundled engine's own path,
  which is the only route left when a rendered body's `${CLAUDE_PLUGIN_ROOT}` arrives unexpanded and
  the exact-path identity check denies every guess.

  The enumeration and the grammar are now one list: `classify_exact_engine_command` rejects any
  subcommand outside `_ALLOWED_ENGINE_SUBCOMMANDS` before its own dispatch, and both bundled script
  paths come from one accessor each, so the message cannot teach a grammar the classifier does not
  implement.

## [0.12.0]

> Version note: `0.11.0` is claimed by the cloud-placeholder fix (#1804, PR #1818), which is open
> against the same manifest. This entry takes the next number so the two do not collide; merge
> #1818 first and this changelog reads contiguously.

### Fixed

- **The engine gate's "provably a different file" escape no longer covers this plugin's own stale
  engines (#1805).** #1640 and #1611 fixed over-gating: a word naming an existing file that is not
  the bundled engine defers, so a consumer's own `tools/hygiene.py` is not mistaken for this engine.
  Claude Code keeps a replaced version's directory on disk after an update, so that same escape also
  covered every **previous version of this engine** sitting beside the current one — each a
  genuinely different file, each deletion-capable, and each answering to nothing but its own
  containment once the always-on gate defers.

  The consequence is a kill-switch bypass, not an unbounded-delete bypass: with
  `disk_hygiene_enabled: false` the plugin-level gate is the only guard whenever the clean skill is
  not the active work, and it deferred. The stale engine's own preview, approval-token, and platform
  blockers still applied. Versions at or below 0.8.1 predate settings-based kill-switch enforcement
  entirely.

  Measured on the audit host: 17 cached version directories, `0.3.0` through `0.10.2`, 16 carrying an
  intact engine (`0.9.4`'s is absent). Against the installed 0.10.2 guard, all 15 non-current engines
  resolve, are not `samefile` with the bundled one, and the plugin-level gate **deferred on an
  `apply --execute` invocation of every one of them**. The documented "about two weeks" retention
  bound does not hold in practice — `0.3.0` is still present — so the window is unbounded.

  The gate now refuses the escape to any path resolving inside
  `<plugins>/cache/<marketplace>/<name>`. That prefix is derived from the guard module's own
  `__file__`, not from argv or the environment, so nothing outside the process can redirect it — the
  same reasoning that keeps the kill-switch read off `CLAUDE_CONFIG_DIR`. A `--plugin-dir` checkout
  carries no such prefix and the narrowing is inert there, which is correct: a checkout has no cached
  siblings, and narrowing on it would gate a contributor's work on their own tree.

  **This does not relax or re-break #1640 and #1611.** A consumer's own engine-named script outside
  the cache still defers, on both the plain and the operator-carrying shapes; verified before and
  after against an identical synthetic cache layout, where the stale sibling flips from `defers` to
  `GATES` while the consumer tool stays `defers` and the bundled engine stays `GATES`.

  **Residual:** a *copied* engine — one carried outside the cache tree — is still outside the prefix,
  as it is outside every identity check the gate makes. That is the copy-evasion class the gate has
  always accepted, and the engine's own preview/approval-token containment remains the authority.

## [0.11.0]

### Fixed

- **Cloud-sync placeholders are now hard-protected instead of being the most attractive target in a
  home audit (#1804).** The engine's only structural defense against cloud-sync content was
  `is_linkish()`, which treats a Windows reparse point as protected. The dominant OneDrive
  dehydrated-placeholder class carries **no reparse bit when read through `os.lstat`**, so the whole
  subtree was walked and every placeholder was recorded as an ordinary file with
  `protected_reasons: []`. Its `logical_size` is the **remote** byte count while local occupancy is
  roughly zero, so the tree also looked like the largest reclaimable win on the volume — and
  deleting a placeholder propagates the delete to the provider, which for a tenant sync root is the
  organisation's only copy.

  Measured on the audit host before the fix: 1,101 files walked, 872 dehydrated placeholders
  totalling 13,770,936,008 bytes, **0 of 872** flagged by `is_linkish()`. After the fix the same
  tree reports 842 entries carrying `cloud-placeholder` (the remaining 30 sit under subtrees an
  existing name protection already truncates), and the only entries left unprotected are the 229
  genuinely local, hydrated files.

  `hard_protection()` now contributes a `cloud-placeholder` reason from the file attributes it
  already reads, so the protection reaches every lane at once — `scan`, `preview`, `handoff-verify`,
  and `apply`'s pre-removal recheck all consult that one predicate. It is deliberately independent
  of the reparse test rather than folded into it: this is precisely the class a reparse test cannot
  see. Both flags are derived from a single `lstat` per ancestor, so the walk's stat load is
  unchanged.

  **`FILE_ATTRIBUTE_RECALL_ON_OPEN` is deliberately excluded from the predicate**, against the
  obvious reading of the attribute names. Its value, `0x00040000`, is the same number as
  `FILE_ATTRIBUTE_EA`, and Microsoft documents `RECALL_ON_OPEN` as appearing "only in directory
  enumeration classes" while every attribute read here comes from `lstat`
  ([File Attribute Constants](https://learn.microsoft.com/en-us/windows/win32/fileio/file-attribute-constants)).
  Read through `lstat` the bit therefore means "has extended attributes": a sweep of two non-cloud
  trees on the audit host found 1,552 fully-local files carrying it, including .NET build output and
  temporary `.node` files. Including it would have protected exactly the artifacts this engine
  exists to reclaim. With the bit excluded, the same 412,270-entry sweep flags **zero** false
  positives while the tenant sync root still flags correctly.

- **A tenant cloud-sync root is protected by name, not only by its contents (#1804).** Attribute
  protection covers placeholder *files*, but measurement showed the containing directories carry no
  cloud attribute at all — 99 subdirectories under the tenant root all read plain `0x10`. A fully
  hydrated sync root therefore has no protected descendant, and deleting it still destroys the cloud
  copy. Name protection was exact-match and shipped the literal `OneDrive` only, so
  `OneDrive - <Organization>` — the documented shape of a OneDrive for Business sync root, whose
  tenant portion varies per installation — matched nothing.

  The baseline now carries a `protected_name_globs` list, matched casefolded through `fnmatchcase`
  so the verdict does not depend on the host platform's case rules. Consumers could not have closed
  this themselves: `protected_exact_names` is not overlay-extensible, and an overlay's
  `additional_protected_path_globs` are matched relative to the scan target, so a standing policy
  protects such a root only when the target happens to be its parent. Protection that must hold for
  every target has to ship in the baseline.

  The list is deliberately short, because a protected name applies at **every depth**: a protected
  directory is never traversed, and it reports `logical_size: 0`, which is byte-identical to a
  genuinely empty directory. Over-protection is therefore not free — it silently under-reports.
  Shipped: the glob `OneDrive - *` (measured on the audit host, and the documented shape of a
  OneDrive for Business sync root), the glob `Dropbox (*)` and the exact name `Dropbox` (Dropbox
  documents both `Dropbox (Personal)` and `Dropbox (<business name>)` as folder names), and the
  exact name `iCloud Drive`.

  Two candidates from the report were **rejected** after checking them. `Box` is a common enough
  directory name in source trees that protecting it at every depth would make ordinary directories
  untraversable and silently zero-sized. `Google Drive` is a legacy Backup-and-Sync name: current
  Google Drive for desktop streams to a virtual drive letter (`G:` by default on Windows,
  [Drive for desktop settings](https://support.google.com/drive/answer/13470231)), not to a folder
  under the user profile.

  Only the OneDrive class was measured. `iCloud Drive` — with the space, the folder name Apple
  documents directly under the Windows user profile — and `Dropbox` were confirmed unprotected by name
  on the audit host, but their file attributes were never sampled, so they are protected on name
  alone and their placeholder behaviour remains unverified.

  Effect on the reported scenario: in a depth-1 scan of the user home, `OneDrive - <Organization>`
  moves from `protected_reasons: []` to `baseline-protected-name`, and the same path is now rejected
  outright as an audit target rather than silently scanned.

### Added

- **Per-entry `size_qualifiers` and `file_attributes` in the snapshot (#1804).** A recorded byte
  count carried no way to say "these are not local bytes", so a placeholder's remote size was
  indistinguishable from reclaimable content. Every entry now records the attribute word `lstat`
  already returned plus a `size_qualifiers` list, and a cloud placeholder is qualified whether or
  not it is protected — protection stops the deletion, and the qualifier stops the misreading. This
  is an additive per-entry trace only; no aggregate's definition changes here.

### Changed

- **The clean skill's positional-triage rule reads an entry's own `protected_reasons`** rather than
  testing membership of `protected_exact_names`. Protection now also comes from name patterns and
  from live filesystem state, and a rule naming a single policy field walks straight past a sync
  root whose name embeds a tenant.

## [0.10.2]

### Fixed

- **The engine gate no longer denies commands naming a DIFFERENT file whose name ends in
  `hygiene.py` (#1611).** `_engine_gate_relevant` decided marker relevance with a bare substring
  test over the command string, so `test_hygiene.py` — this plugin's own test suite — read as an
  engine invocation. In any consumer session with the plugin enabled, that denied the natural
  commands for working on it: `python3 -m unittest -v .../test_hygiene.py` and
  `ruff check .../test_hygiene.py` were both refused, on the Bash tool and on PowerShell. The
  literal-parse path was already correct — it basename-matched (`Path(word).name == _ENGINE_MARKER`)
  and deferred — so only the operator-carrying path misfired, which is why the failure looked
  arbitrary: the same command gated or deferred depending on whether it contained a `&&`.
  Relevance now uses that same basename equality everywhere, via one `_carries_marker` helper, so
  the two paths agree on what "is the engine" means.

  **This is a precision change, not a relaxation.** A basename test is only as good as the tokens
  it reads, so the narrowing is paid for by deriving those tokens as maximal runs of path-legal
  characters (`[^A-Za-z0-9._\-/\\:]+` as the delimiter). Enumerating shell syntax instead would be a
  losing game — an assignment glues the filename with `=`, a list with `:`, a metacharacter with
  `;` — and missing any one of them silently un-gates a real invocation. Inverting the question is
  total: `hygiene.py` is spelled entirely from the kept characters, so splitting on everything else
  can only expose the engine filename, never hide it. `engine=hygiene.py && python3 "$engine"
  apply`, `FOO=1 BAR=hygiene.py python3 "$BAR" apply`, `foo;hygiene.py`, `$(hygiene.py scan)`, and
  `true|hygiene.py` all still gate.

  Identity still outranks the filename for the newly-deferred name. Because `test_hygiene.py` no
  longer carries the marker, it routes to the marker-free branch, whose job is to catch a LINK to
  the engine under another name — and that branch scanned only whitespace tokens, so an operator
  glued to the path (`/tmp/test_hygiene.py;echo done`) left `...;echo` attached, `samefile` resolved
  nothing, and a link to the real engine deferred. The path-legal tokens are scanned there too now,
  which can only ever gate more. A link to the engine named like the suite gates beside `;`, `|`,
  and `&&`, and now also gates with no operator at all, where it deferred before this release.

  A relative marker path in an operator-carrying command is now treated as unknowable rather than
  provable. The "provably a DIFFERENT file" escape resolves a token against the **guard's** working
  directory, but that branch is reached precisely because the command carries an operator — and an
  operator can be a `cd`. From a directory holding an unrelated `hygiene.py`,
  `cd <plugin-scripts>;./hygiene.py scan` let the escape "prove" a different file and defer while
  the shell ran the bundled engine. The escape now requires an absolute path. This also closes two
  pre-existing fail-opens of the same shape (`cd <plugin-scripts> && ./hygiene.py apply` and its
  bare-name spelling), which deferred before this release. **Behavior change worth noting:** a
  consumer invoking its own `hygiene.py` by RELATIVE path inside an operator-carrying command
  (`python3 ./hygiene.py --help && echo ok`) now gates where it previously deferred. That is the
  fail-closed direction and it is deliberate — the guard cannot know which directory that path is
  relative to; an absolute path still defers.

  Two further shapes are handled where the token alone is not enough. A Bash line continuation is
  removed before tokenizing, because the shell eats `\` + newline while reading the line and
  otherwise it stays welded to the filename as `hygiene.py\`, hiding a multi-line invocation of the
  real engine. And the basename is taken by splitting on both separators rather than with
  `Path().name`, which is platform-flavoured: `PureWindowsPath("/x/hygiene.py\")` yields
  `hygiene.py` while `PurePosixPath` keeps the backslash, so a `Path`-based predicate would gate on
  Windows and fail open on Linux.

  Copy-evasion coverage is untouched because it never routed through the marker: a link to the
  engine under any other name gates by `os.path.samefile` identity, and a byte copy remains the
  accepted residual the function's docstring already names.

- **The engine gate no longer denies a consumer's own `hygiene.py` because of how its parent
  directory is spelled (#1640).** Detection wants aggressive splitting and resolution wants whole
  paths, and one token list was serving both. The "provably a DIFFERENT file" escape requires an
  ABSOLUTE path, but it read the path-legal fragments — so any character outside that class split a
  consumer's absolute path and left the fragment carrying the filename relative, unprovable, and
  denied: `python3 /tmp/consumer+tools/hygiene.py --help && echo done` gated a file that has nothing
  to do with this plugin. `~` is what makes this ordinary rather than exotic — a Windows 8.3
  short-name segment (`C:\Users\<user>~1\...`) puts unpunctuated paths under ordinary temp
  directories into the same population. Resolution now reads the whole shell word containing the
  token, with quoted spans kept intact so a path with spaces resolves too, while detection keeps the
  fine tokens exactly as they were.

  The widening cannot travel: a token is paired with its enclosing word by SPAN, never by substring
  containment, so a marker token is only ever proved a different file by its OWN word.
  Containment-based pairing would let `python3 /abs/consumer/hygiene.py --help && python3
  hygiene.py apply` borrow the first word's absolute path to "prove" its bare second invocation
  different, and defer while the real engine ran. **Residual, deliberately left:** an operator with
  no surrounding whitespace (`python3 /tmp/c+x/hygiene.py&&echo done`) still gates, because the
  whole word is then `/tmp/c+x/hygiene.py&&echo`, which resolves to nothing. That is the fail-closed
  direction, and widening the tokenizer to chase it would re-open the gluing seam this release
  exists to close.

- **A filename spelling the FILESYSTEM resolves to the engine no longer bypasses the gate.** Win32
  discards trailing dots and spaces from a filename and resolves `::$DATA` to the main data stream,
  so `cd <plugin-scripts> && python hygiene.py. apply` opened and ran the kill-switched engine while
  no token's basename was the marker — the guard deferred. 8.3 short names are a third spelling of
  the same kind. The fix asks the filesystem instead of listing spellings: a relative word is
  identity-checked against the ENGINE'S OWN directory, which is precisely the directory such a
  command must `cd` into for the alias to run. That closes trailing dots, trailing spaces, NTFS
  stream suffixes, and short names in one move, where enumerating them closes one per review round.
  The name predicate is unchanged and stays platform-independent; identity is what carries this.

  Verified as a differential against the pre-change guard over 89 command shapes — engine
  invocations, wrappers, assignments, concatenations, substitutions, pipes, backticks, redirects,
  line continuations, post-`cd` relative paths, linked aliases, filename aliases, punctuated and
  short-name consumer paths, proof-borrowing shapes, mentions, and near-miss names. Every shape
  holds its prior verdict except the intended ones: four filename-alias shapes and one path-list
  assignment move toward GATING, and fourteen consumer-path shapes move toward deferral. The suite
  gained four regression tests, including a mechanical check that the span-located token partition
  is identical to the split partition it mirrors, so a future refactor cannot quietly change what
  detection reads.

## [0.10.1]

### Documentation

- **Safety model now documents the live agent scratchpad hazard (#1637).** `machine-health`'s new
  `claude-temp-root` check routes its findings here, which makes a Claude Code temp root a named
  target for this skill. Its hazard is not the session running the clean but a *concurrently
  running other* session, whose scratchpad is an active working directory with no marker separating
  it from an abandoned one — and directory age cannot separate them, since a long-running session's
  scratchpad is old and live at once. The new "Live agent scratchpads" section records that no new
  machinery is needed: live-handle proof, live re-discovery of VCS markers, identity-and-descendant
  equality since snapshot, and immediate verdict expiry already hold the line structurally rather
  than by heuristic. It also states the two consequences plainly — a Windows temp root is a
  manual-lane job because the engine returns `execution-platform-unsupported` there, and a temp root
  is a low-confidence target however large it looks, because the tier follows what can be proven
  quiescent rather than what would be reclaimed. No behavior change.

## [0.10.0]

### Changed

- **`clean`'s approval points now state an invariant plus a conditional surface, instead of naming
  `AskUserQuestion` as the only way to confirm (#1724).** All three — the §1 large-scan confirmation,
  the §5 removal approval, and the §6 unsupported-platform handoff — named that tool. It is not always
  in the pool: permission mode `dontAsk` denies it unconditionally, a bare-name `permissions.deny`
  rule removes it from Claude's context entirely, and a `disallowed-tools` entry removes it from the
  pool while the skill is active — each leaving the text naming something absent. A new
  **Confirmation gate** section owns both halves once: the bar (the
  user's own affirmative answer, in this interactive session, naming exactly the tier and path list
  just shown; no prior general request, `--execute`, "clean everything", approval of another tier, or
  silence; never self-supplied or inferred; stop on rejection) and the surface (`AskUserQuestion`
  preferred because its answer cannot be fabricated, an inline numbered question when it is absent).
  The three sites now point at it rather than restating it. **The bar is unchanged**, and this
  plugin's model-independent floor is untouched — the skill-scoped hook still blocks ad-hoc deletion
  and still forces a final permission prompt for the exact engine `apply`, and the approval token
  still binds an apply to the previewed plan.

## [0.9.7]

### Fixed

- **A broken *stdout* turned the guard's deny into a fail-open (#1524), the seventh of the class
  #1449 closed and the one none of its in-process tests could see.** `_decide`'s decision `print`
  only buffers, so a closed stdout pipe raises nowhere inside `main` — the failure surfaces at
  interpreter shutdown, and CPython reports that by replacing the exit status with `120`. Measured on
  the merged code: a `deny` decision with stdout wired to a pipe whose reader is closed exited `120`,
  which PreToolUse treats as non-blocking, so the destructive command runs even though the guard
  decided to deny it. The module tail now flushes stdout itself, catching an undeliverable decision
  while there is still a decision to make — it denies at exit `2` with a diagnostic, because a
  decision the host never received is not a decision — then flushes stderr best-effort and
  `os._exit`s the resolved code, so a shutdown flush can no longer rewrite it. Reuses
  `_write_diagnostic`'s null-device fallback, extracted as `_discard_stream`. Covered by a
  real-subprocess `GuardTests` case against a genuinely closed stdout pipe (the in-process helpers
  never reach interpreter shutdown, so they cannot reproduce it).

  **Also closes #1526's independently-reported trigger (fd 2 closed outright, not merely broken) as a
  structural side effect**, without touching `_discard_stream` itself. #1526 exists because
  `_discard_stream`'s null-device repair can self-undo: when `os.open(os.devnull, ...)` happens to
  return the very fd being repaired (POSIX allocates the lowest free descriptor, so a *closed* fd 2
  is reused rather than a fresh one), `os.dup2` is a no-op and the following `close` re-closes it —
  and the pre-#1524 tail (`raise SystemExit(main())`) then hits that closed fd during the
  interpreter's own shutdown flush and gets rewritten to `120` the same way. Every exit path now ends
  in `os._exit` instead, which never runs that shutdown flush, so nothing downstream depends on
  `_discard_stream` having actually repaired the fd — the latent self-undo bug it describes is still
  present in `_discard_stream`, but can no longer surface as a rewritten exit code. Covered by a
  second real-subprocess case that closes fd 2 outright and forces the internal-error deny path;
  213 tests pass.

## [0.9.6]

### Fixed

- **The destructive-action guard could fail open on exit 1 with no diagnostic (#1423), distinct from
  #1242.** #1416's transcript sweep turned up one recorded occurrence: the plugin-level
  `hooks/hooks.json` `destructive_guard.py --mode engine-gate` hook launched successfully, ran for
  17054 ms, then exited `1` with empty stderr — the post-#1242 command shape, not the
  `${user_config.*}` launch-refusal bug #1242 already fixed. Per the
  [hooks reference](https://code.claude.com/docs/en/hooks) (fetched 2026-07-25), PreToolUse treats
  exit `1` as non-blocking and proceeds with the tool call — only exit `2` blocks — so the guard
  itself never issued a deny, ask, or allow: it simply stopped, and the destructive command ran
  ungated. The defect: only the top-of-`main` JSON-payload parse was wrapped in a `try`/`except`;
  every line of decision logic after it (now extracted into `_decide`) had no exception handling at
  all, so any bug or unexpected exception in that path fell through to Python's default
  unhandled-exception behavior — exit 1, silently. `main` now wraps the entire `_decide` call in a
  `try`/`except BaseException`, so any exception the guard's own code raises past the payload parse
  denies (exit `2`, one-line diagnostic on stderr naming the exception type and message) instead of
  falling open; exit `1` is no longer reachable from any internal path in the guard (`test_hygiene.py`
  `GuardTests` now injects a failure into `_decide` directly, into every function `_decide` calls in
  its real belt- and engine-gate-mode call graph — `resolve_mode`, `_engine_gate_relevant`,
  `resolve_disk_hygiene_enabled`, `resolve_authorized_data_root`, `is_exact_kill_switch_probe`,
  `classify_exact_engine_command`, `powershell_decision` — and a bare `KeyboardInterrupt`, asserting
  exit `2` with non-empty stderr and exit `1` never observed, in every case).

  **The 17-second duration investigated, not characterized (single unreproduced occurrence).** Every
  filesystem call already reachable from this module (`Path.resolve(strict=True)`,
  `os.path.samefile`, `Path.stat`/`read_text`) already caught `OSError` at its own call site, so a
  stall ending in `OSError` would not by itself explain an *uncaught* exception — narrowing the field
  without settling it. The strongest identified candidate for the stall itself, not for the exit-1
  bug: `_engine_gate_relevant`'s marker-free fallback calls `os.path.samefile` on every
  separator-containing word of *every* Bash/PowerShell command in *every* session (not only
  disk-hygiene commands) while resolving the plugin-level engine gate — an unreachable or slow-to-stat
  path referenced by an ordinary, unrelated command is a real, user-reachable way to block this hook
  for seconds. What argues against a plain uncaught exception as the full story: empty stderr is not
  what Python's default unhandled-exception handler produces (it writes a traceback), which leaves an
  external process kill (antivirus/EDR scanning `python3`, a transient OS resource issue) as an open,
  unconfirmed possibility this module cannot fix from inside the interpreter — a truly externally
  killed process cannot run Python code to change its own exit behavior. What IS fixed regardless of
  which of these it turns out to have been: the guard now self-enforces an internal watchdog deadline
  (`DISK_HYGIENE_GUARD_WATCHDOG_SECONDS`, default 10s — comfortably above every legitimate
  invocation, which completes in milliseconds, and below the one observed 17054 ms occurrence) that
  denies (exit `2`, diagnostic on stderr) on a background timer if `_decide` has not returned by the
  deadline, instead of risking an unbounded hang toward the harness's own (600s-default) hook timeout.
  Both guard registrations (`hooks/hooks.json`'s plugin-level engine gate and `skills/clean/SKILL.md`'s
  skill-scoped belt) now also declare an explicit `timeout: 60` as a harness-level backstop, well
  below the previous implicit 600s default, in case the internal watchdog itself is ever prevented
  from running — the same proven value `guardrails` raised its own blocking PreToolUse guards to
  (`plugins/guardrails/CHANGELOG.md` `[0.15.1]`: 10-40x headroom over every real duration sample
  measured, well short of the 600s platform default), not the 20s this plugin started at.

- **Four residual fail-open paths in the new watchdog itself, all reported in review.** (1) Arming
  the watchdog sat *outside* the exit-2 boundary it protects: under OS thread or memory exhaustion
  `threading.Timer(...)` / `.start()` raises `RuntimeError: can't start new thread`, which reached
  the interpreter's default handler — exit `1`, non-blocking, destructive command proceeds. Failing
  to arm the guard's own deadline is exactly when the guard must deny, so construction and startup
  now run inside the protected boundary and fail closed at exit `2`. (2) `_watchdog_seconds`
  validated its `DISK_HYGIENE_GUARD_WATCHDOG_SECONDS` override with a bare `> 0` test, which `inf`
  (and `1e400`, which parses to `inf`) passes; `threading.Timer(inf, ...)` then accepts `start()`
  and dies *in the timer thread* with `OverflowError: timestamp out of range for platform time_t`,
  silently disarming the watchdog while the guard looks armed — and because it raises off the main
  thread, the exit-2 boundary never sees it. Non-finite overrides now fall back to the default like
  every other invalid value. (3) The watchdog was armed *after* `json.load(sys.stdin)`, so a stall
  in the stdin read itself — e.g. a Windows Win32-pipe late EOF, where the OS delivers the complete
  JSON payload but delays the EOF signal (the same class `guardrails` bounds in its bash hook fleet
  via `hook::buffer_stdin`, `plugins/guardrails/CHANGELOG.md` `[0.8.0]`) — ran with no deadline armed
  at all, so the declared hook `timeout` would fire first and the harness would cancel the hook with
  no `permissionDecision`, the exact non-blocking fail-open #1423 exists to close. The watchdog now
  arms as the first action inside `main`'s fail-closed boundary, before the stdin read. (4) A valid
  but large override inverted the two deadline layers: the watchdog is the primary mechanism and the
  declared hook `timeout` is the backstop, which only holds while the watchdog fires *first*, so
  `DISK_HYGIENE_GUARD_WATCHDOG_SECONDS=600` meant the harness killed the process instead — and a
  killed PreToolUse hook yields no `permissionDecision`, so the command proceeds unguarded. Overrides
  are now clamped to `_WATCHDOG_MAX_SECONDS` (the declared 60s hook timeout less 10s of headroom the
  watchdog structurally cannot cover: interpreter startup before `main` runs, plus teardown after the
  timer fires). The guard cannot read its own hook `timeout` — a PreToolUse payload does not carry it —
  so that value is duplicated in code and pinned to both registrations by
  `test_declared_hook_timeouts_match_the_watchdog_ceiling`, which fails the suite if either drifts.
  All four paths are covered by new `GuardTests` cases, including a real-subprocess test with stdin
  opened as a pipe that is never written to or closed (a stalled read on the host running the suite,
  not only a Windows Win32-pipe late EOF, reproducing the general "blocked in read" shape without
  needing that platform specifically); 209 tests pass.
- **A fifth fail-open path: the deny diagnostic could preempt the deny itself.** Both fail-closed
  exits write a one-line explanation to stderr first, and both wrote it with a bare `print`. If the
  hook host has closed or lost the stderr pipe, that `print` raises `BrokenPipeError` from inside the
  very handler about to deny — the exception escapes before `return 2` in `main` or `os._exit(2)` in
  `_watchdog_fire` runs, and the process exits with a status PreToolUse treats as non-blocking, so
  the destructive command proceeds ungated. On the timer thread it is worse: an exception there never
  reaches `main`'s exit-2 boundary at all. Both sites now route through `_write_diagnostic`, which
  makes the write best-effort — the deny is carried by the exit code, and losing the message is
  acceptable where losing the deny is not — and, on a failed write, points fd 2 at the null device so
  the interpreter's own shutdown flush of a still-buffered stderr cannot raise either (that failure
  exits 120, likewise non-blocking). Covered by two new `GuardTests` cases, one per exit site; 211
  tests pass.
- **`GuardTests` no longer reads an operator's own watchdog override as the default.** The deadline
  is overridable by environment variable — the guard's own timeout diagnostic tells operators to
  export it — so a value already exported in the shell running the suite leaked into every
  assertion about the DEFAULT deadline and failed it against a correct implementation. The class's
  `setUp` now strips that variable for the whole class; the cases that exercise an override still
  set it explicitly.

## [0.9.5]

### Fixed

- **A silent `destructive_guard.py` launch/runtime failure is now surfaced instead of looking
  identical to an approval (#1416).** A repo-operator investigation of the original #1416 report
  found both cited launch-refusal root causes already fixed and merged (#1242/0.9.0 here,
  repo-hygiene's own guard by #1006); what remained live was that "the guard denied nothing because
  it approved" and "the guard denied nothing because it never ran, or ran and died" were
  indistinguishable from outside the harness. A new detector,
  `skills/clean/scripts/guard_launch_monitor.py`, registers as a second, independent hook in
  `hooks/hooks.json` — on `Stop`, not `PreToolUse`/`PostToolUse`, to avoid repeating the per-tool-call
  cost class documented in
  `docs/adr/0004-rightsize-instruction-surfaces-by-incumbent-first-arbitration.md`'s D-12 — and
  scans the session transcript's tail for `hook_non_blocking_error` records naming
  `destructive_guard.py`. On a match it emits one `systemMessage` per session (never a block, never a
  `permissionDecision`) naming the guard, the failure count, and the most recent failure's exit code,
  duration, and truncated stderr. It is a separate, stdlib-only process — deliberately not wired
  through the guard's own code, since a guard that cannot launch cannot report that it did not
  launch — and fails silently closed on any read/parse error so it can never itself become the
  reason a turn is blocked. It covers only `destructive_guard.py`'s own command string: repo-hygiene's
  guard is out of scope (verified working separately), there is no retroactive scan of prior
  sessions, and — because both hooks are wired with the same literal `python3` command — the
  interpreter-resolution fail-open documented in the README (the WindowsApps alias stub, or a
  missing/broken `python3`) takes the detector down with the guard, so that one vector stays
  unreported until the detector gets a launcher independent of the guarded interpreter (#1504). The
  bounded tail read discards its first line only when the retained window actually starts mid-record:
  when `size - _MAX_TAIL_BYTES` lands exactly on a record's first byte, an unconditional discard threw
  away a whole record — which can be the session's only guard failure, silencing the very report the
  detector exists to make. The once-per-session marker is written only after the warning has actually
  left the process (`print` then `flush`, then mark): marking first meant a closed pipe or a kill
  between the two silenced every later `Stop` in the session while the broad never-fail-loudly handler
  exited quietly — reinstating the silence the detector exists to break.

## [0.9.4]

### Fixed

- **Headless reconfigure recipe now preserves install scope (#1406).** The `claude plugin
  uninstall` → `claude plugin install ... --config` recipe in `skills/setup/SKILL.md` defaulted
  both halves to `-s user`. When this plugin is installed at `project` or `local` scope, that
  silently uninstalled a separate user-scope record while the effective project/local install kept
  loading, and the reinstall landed at a scope that does not load. Both commands now carry
  `-s <scope>`, sourced from what `claude plugin list` reports for this plugin — the same fix
  already applied to `session-flow` and `rate-limit-guard` in #1393.

## [0.9.3]

### Fixed

- **`setup check` now detects the Windows Store `python3` alias stub that fails the guard open
  (#1110).** The `clean` destructive-action guard hook launches the literal command `python3`. On
  stock Windows that name resolves to a zero-length `WindowsApps\python3.exe` App Execution Alias — a
  reparse stub that opens the Microsoft Store instead of running an interpreter, so the guard process
  never starts. A PreToolUse hook blocks a tool call only by emitting exit code 2 or a `deny` decision;
  a guard that never runs emits neither, so Claude Code lets the destructive Bash/PowerShell command
  proceed ungated. This recurs the 0.6.3 fail-open shape (hook launch failure treated as non-blocking)
  through a new vector — the guard's launch name resolving to the Store stub rather than a real
  interpreter. `setup check` now runs a bundled inspect-only probe
  (`skills/setup/scripts/python3_alias_probe.py`, covered by `test_python3_alias_probe.py`) that
  classifies the `python3` resolution — zero length under a `WindowsApps` path component is the stub —
  without executing it, and orders the check so nothing (including the version-floor probe itself)
  executes the bare name `python3` until that verdict is `ok`: the probe is launched via an
  already-proven interpreter (`py -3`, `python`, or an absolute path), with a direct PowerShell
  inspection of the resolved path as the interpreter-less fallback. The check fails closed on every
  verdict except `ok`: the stub and an
  unreadable-identity (`indeterminate`) verdict both FAIL with remediation (disable the App execution
  alias, or put real Python ahead of WindowsApps on `PATH`), and an absent `python3` folds into the
  floor's missing-interpreter FAIL. The disabled-toggle FAIL→INFO downgrade is exempted for every
  step-1 failure: audit-only mode is enforced by the guard, both guard surfaces launch the
  literal name `python3`, and a guard that never runs can neither read nor enforce the configured
  `false`. So every non-`ok` verdict (`store-alias-stub`, `indeterminate`, `not-found`) stays fatal;
  so does a nominally `ok` resolution whose version probe then fails to launch at all — a corrupt
  or zero-length binary outside `WindowsApps`, a broken shim, a permission error; and so does an
  interpreter that starts but reports a version below the floor, because launching the version probe
  proves only that something executes, not that it can run the guard's own source (Python 3.6, for
  example, rejects the guard's `from __future__ import annotations` and exits without a deny, which
  PreToolUse treats as non-blocking). The suite's test wrapper
  applies the same inspection to its own interpreter candidates before executing them. The README
  requirements section documents the vector.

## [0.9.2]

### Fixed

- **The anchored target root is validated by object identity, so benign directory churn no longer
  aborts an approved run (#384).** Preview and apply held the target root to full stat identity
  (`st_mtime_ns` and `st_size` included), but a directory's mtime and size flip whenever any direct
  child is added or removed. Human approval sits between scan and apply, so any unrelated write into
  a live target — a home or an active project root, the common case — flipped the root's mtime and
  aborted the run with "anchored target changed since the snapshot," forcing a full rescan. Both
  sites now use the stable device/inode/type identity that directory candidates and `handoff-verify`
  already use; a replaced root still refuses. The check was never wrong-deleting, only over-refusing.

### Changed

- **`resolve_snapshot_target` no longer takes `strict_root_stat`.** With one root-identity standard
  across preview, apply, and `handoff-verify`, the parameter that selected between them is gone and
  the single refusal reads "target root was replaced since the snapshot."

## [0.9.1]

### Changed

- **The PowerShell lane's documented coverage now names what it does not flag (#386).**
  `reference/safety-model.md` and the clean skill's PowerShell gotcha described the lane as gating
  "known deletion spellings" without stating that destructive non-deletion spellings — `Move-Item`,
  `Rename-Item`, overwriting writers (`Set-Content`/`Out-File`/`>`/`New-Item -Force`), and
  `Format-Volume`/`Clear-Disk` — reach the tool with no guard verdict, audit-only mode included. The
  gap is now disclosed where the security model is stated, naming the consumer's permission policy as
  its only backstop — the manual handoff's per-path approval covers the paths selected for removal, so
  it does not reach what these spellings collaterally destroy. Docs only; the guard's behavior is
  unchanged and closing the gap is tracked in #387.

## [0.9.0]

### Fixed

- **The `disk_hygiene_enabled` kill switch now enforces on both guard surfaces — closing the
  inert-by-default engine gate (#1019).** Through 0.8.3 the plugin-level engine gate (`hooks/hooks.json`)
  carried a bare `${user_config.disk_hygiene_enabled}` argument. Because the declared userConfig `default`
  is unimplemented upstream (#46477 / #39455 / #39827), an unset-but-defaulted token dropped the whole hook
  entry, so on a default install the gate never ran; the skill-frontmatter belt could not receive the value
  either (skill hooks get neither the `${user_config.*}` substitution nor `CLAUDE_PLUGIN_OPTION_*`). Audit-only
  mode therefore degraded from deny-outright to prompt-gated. Both surfaces now resolve the toggle by
  **reading it directly** from user-scope `pluginConfigs` in `settings.json`, so a configured `false` is
  denied outright on the Bash engine lane and the PowerShell deletion lane, whether or not the clean skill
  is active.

### Changed

- **Kill-switch delivery is a settings read, not a hook argument or environment variable.** The engine gate
  drops its `${user_config.*}` argument (fixing the hook-drop) and both surfaces call the new shared
  `lib/killswitch_config.py` reader. The user `settings.json` is located **solely** from the
  tamper-resistant `${CLAUDE_PLUGIN_ROOT}` both surfaces receive — the guard never falls back to
  `CLAUDE_CONFIG_DIR`/`HOME` for it, because those are environment values a repo `.claude/settings.json`
  `env` block can inject into hook subprocesses (carrying no provenance). A marker-less `--plugin-dir`
  checkout root leaves no trusted user path, so the user scope is skipped and the switch relies on managed
  settings, failing closed to enabled otherwise. Since Claude Code 2.1.207 `pluginConfigs` is honored only
  from user, managed, and `--settings` scope (project/local ignored), so a hostile repo cannot forge the
  value. Every absent, unreadable, or ambiguous read fails **closed to enabled**.
- **Managed (enterprise) settings are honored as the highest-precedence scope.** The reader also reads the
  platform managed-settings.json (`/Library/Application Support/ClaudeCode/` on macOS, `/etc/claude-code/`
  on Linux/WSL, `C:\Program Files\ClaudeCode\` on Windows — a fixed path, not `%ProgramFiles%`-derived, so a
  repo `env` block cannot redirect it); a value configured there overrides the user file, so an organization
  can enforce audit-only mode; the sibling `managed-settings.d/` drop-in directory is merged over it
  (later files win). The reader also matches only this install's exact `<name>@<marketplace>` key
  (derived from `${CLAUDE_PLUGIN_ROOT}`), so another marketplace's `disk-hygiene` entry cannot mask it. The
  one residual: a value supplied only through a session `--settings` file (a runtime CLI flag no hook can
  observe) is not enforced by the guard.
- **`kill_switch_probe.py` now delegates to the shared reader** (its behavior and single-line JSON output
  contract unchanged) so the report-only probe and the guard resolve the switch one way, not two.
- Docs corrected across `clean`/`setup` `SKILL.md`, `reference/safety-model.md`, and `README.md`: the
  "engine gate is inert until configured" and "audit-only reaches only the model, not the guard" caveats
  are removed; the guard is again the audit-only backstop.

### Design note

- This supersedes the planned SessionStart-hook + state-file delivery ("C′"). Both guard surfaces are the
  same script funnelling through one resolve point, so there is nothing to distribute between sessions or
  surfaces: a direct read is a smaller trust surface (a settings *read*, no state-file *write*), honors a
  mid-session settings change, and needs no session-start timing dependency. Semantics are unchanged from
  the locked resolver decision — read user-scope `pluginConfigs`, ignore env, fail closed to enabled.

## [0.8.3]

### Fixed

- **RETRACTS 0.8.2's PowerShell claim, which was wrong (#1195).** 0.8.2 documented that "PreToolUse guards
  do not intercept PowerShell-tool commands" and scoped the PowerShell lane behind a preview caveat. A
  fresh-session controlled test falsified that: a `Bash|PowerShell` PreToolUse matcher **does** fire for the
  PowerShell tool on 2.1.218, the payload `tool_name` is literally `PowerShell`, and a live `Set-Content`
  through that tool was blocked. There is no harness firing divergence and no preview limitation involved —
  0.8.2's caveat overstated an un-isolated inference and is removed.
- **The real defect, now documented accurately: the plugin-level engine gate is inert whenever
  `disk_hygiene_enabled` is unconfigured.** `hooks/hooks.json` passes a bare
  `${user_config.disk_hygiene_enabled}`; upstream never implemented the declared userConfig `default`, so an
  unset-but-defaulted token is neither substituted nor exported as `CLAUDE_PLUGIN_OPTION_*` and its presence
  **drops the entire hook entry** (proven: token-carrying hooks vanish while token-free controls fire, and
  return once the key is configured). So the gate has never run for any consumer who never set the key — on
  Bash and PowerShell alike, which is the real shape of the reported "PowerShell bypass". The skill-scoped
  belt carries no such token and is unaffected. Every doc that claimed the gate "fires in every session"
  or that audit-only mode is "guard-enforced" corrected: the `clean` and `setup` `SKILL.md` files,
  `reference/safety-model.md`, and the consumer `README.md`. The code fix (a delivery channel that does
  not depend on the unimplemented `default`) is tracked separately.
  Recheck when the upstream gap closes (#46477 / #39455 / #39827).

## [0.8.2]

### Fixed

- **Docs no longer promise PowerShell-tool deletion protection that does not fire on current builds
  (inbox `173656`).** `skills/clean/SKILL.md` and `reference/safety-model.md` asserted the PowerShell
  guard belt "turns deletion spellings into a final human permission prompt" and that a configured
  `disk_hygiene_enabled=false` blocks the PowerShell lane. On Claude Code 2.1.218 (Windows, reproduced)
  a `Bash|PowerShell` PreToolUse hook fires for the Bash tool but does **not** intercept
  PowerShell-*tool* commands — the PowerShell tool is a documented *preview* feature
  ([tools-reference](https://code.claude.com/docs/en/tools-reference)) and PreToolUse interception of it
  is not a listed preview limitation, so the belt and the kill switch's reach into the manual PowerShell
  lane are inert there. The claims are now scoped as the guard's *intended* design with an explicit
  version-pinned preview caveat + recheck trigger; on Windows the protections that actually hold are the
  manual lane's per-path `handoff-verify` approval and the consumer's baseline permission policy.
  Observed effect only — the mechanism (matcher firing vs Windows payload delivery vs `tool_name`) is not
  yet isolated (recheck by adding a logging `PreToolUse` `matcher: "PowerShell"` hook in a fresh session
  and confirming it fires for a PowerShell-tool command); the upstream docs-vs-behavior divergence is
  held for a report once isolated.

## [0.8.1]

### Changed

- **`--execute` now gates every deletion lane, including the manual handoff (#1113, F7).** A
  deliberate semantic unification, not a restatement: the flag previously read as "offer the gated
  ENGINE lane", which can never apply on Windows/macOS — leaving the manual lane's gate ambiguous,
  and consumer sessions read it both ways (one proceeded to manual deletion without `--execute`).
  The clean skill now states the unified contract in one sentence at the argument definition and
  requires `--execute` in the manual-handoff precondition, for lane symmetry.

### Fixed

- **Doc corrections from the 0.6.4 consumer audit (#1113, F9/F10).** Safety-model trust boundaries
  now name standing-policy `additional_hints[].reason` prose as untrusted claims requiring
  independent evidence (additive-only design means hints cannot authorize, but the prose reached
  triage reasoning unlabeled). Setup SKILL.md and the README now say `preview` *reports
  `execution-platform-unsupported` as a per-candidate blocker* rather than "returns" it (it was
  never a top-level status), and the README states once that the Recycle-Bin / Trash naming is a
  model-layer distinction only — the engine treats Windows and macOS identically. F10(c)'s
  restructure-the-hub suggestion is DECLINED with evidence: the repo's `.markdownlint-cli2.jsonc`
  sets `"MD013": false` (no line-length rule — the complaint came from an out-of-repo lint run) and
  the skill-quality gate passes the hub at its current length.

## [0.8.0]

### Added

- **`hygiene.py handoff-verify` — deterministic revalidation for the manual lane (#1109).** New
  read-only subcommand: takes the snapshot plus the human-approved exact path list
  (`{"version": 1, "paths": [...]}`, same containment rules as plan candidates) and reruns the
  engine's identity/reparse/protection/descendant/VCS/handle checks per path against live state,
  emitting one machine-readable verdict each — `clear` / `drifted` / `gone` / `contested` — and
  never deleting anything. Platform execution blockers deliberately do not apply (the subcommand
  exists exactly where apply is unsupported); every unverifiable condition fails closed into
  `contested`. Exit 0 all-clear, exit 3 otherwise. The target-root gate reuses preview's checks but
  tolerates the root directory's own metadata churn (stable device/inode/type identity instead of
  full stat identity — deleting an approved root-level item changes the root's mtime, and the
  manual lane deletes one item at a time with a re-verify between items); a replaced root still
  refuses. The clean skill's manual-handoff lane now writes `handoff-paths.json`, runs
  handoff-verify immediately before deletion, and acts only on verdict-`clear` paths — bringing
  snapshot binding to Windows/macOS without adding an engine deletion lane (captures most of the
  declined F12 value; #1116's affirmation records this as the intended alternative). The Bash
  guard admits the exact `handoff-verify --snapshot <s> --paths <p> [--data-root <d>]` shape as a
  read-only invocation, including in audit-only mode (kill switch keeps blocking every deletion
  lane; verification is reporting). Safety model documents the verdict vocabulary and the
  emission-time-only validity of `clear`.

## [0.7.3]

### Added

- **Test coverage for the least-observable engine paths (#1114).** Test-only release — no engine
  behavior change. The paths a consumer can least verify live now have direct tests with mocked OS
  surfaces, exercised identically on both CI lanes regardless of host platform:
  `windows_handle_state` CreateFileW error-code mapping (32/33 → open, 5/1314 → needs_elevation,
  unknown codes fail closed as unverified; handle closed on success; directory probes use
  backup semantics), `posix_handle_state` lsof parsing (missing lsof, diagnostics on stderr,
  unexpected exit codes, and timeouts all fail closed; directory vs file command shapes),
  `windows_storage_sense_state` registry reads (set/zero/missing values, missing key),
  `_decode_mountinfo_path` octal decoding (escapes, non-octal and truncated sequences left
  verbatim), and the non-Git VCS marker branch (nested, enclosing, and casefolded markers all
  flag `vcs-state-unverified`). No latent engine bugs surfaced while writing them.

## [0.7.2]

### Fixed

- **PowerShell lane narrows the engine deny from substring to invocation classification (#1112).**
  The lane denied ANY command containing the substring `hygiene.py` — blocking commands that
  merely NAME the script (live-observed, F6) while a renamed copy evaded it anyway. The engine
  check now uses the same invocation classifier as the plugin-level gate (bundled-file identity +
  launcher rules): bare-name and consumer-file mentions defer. Deliberately NOT deferred: a
  command whose argument IS the bundled engine, even under a read-verb spelling
  (`Get-Content <engine>`) — PowerShell aliases and profile functions shadow cmdlet names, so a
  verb name proves nothing about what executes (review finding); the deny message points at
  non-shell file tools for reading the engine source.

## [0.7.1]

### Fixed

- **PowerShell mutation guard covers instance-method `.Delete()`, and robocopy mirror/purge/move
  (#1111).** The .NET-delete pattern required `::` before `delete`, so `$item.Delete()` executed
  with no guard flag (live-observed in the 0.6.4 consumer audit, F4); it now also matches
  `.Delete(`. `robocopy` with `/MIR`, `/PURGE`, `/MOV`, or `/MOVE` (mass deletion via mirroring)
  now raises the final ask prompt and is denied in audit-only mode; plain `robocopy /E` copies
  stay untouched. The truncation family (`Set-Content`, `Out-File`, `New-Item -Force`) is
  DECLINED with reason: those spellings are ordinary file-writing work, and an ask-tier belt that
  fires on every write during a cleanup session trades too much friction for a raised bar the
  engine's own containment already backs — design stays raised-bar-not-fail-closed.

## [0.7.0]

### Added

- **Split guard registration — plugin-level engine gate delivers the kill switch and data-root
  authority (#1105, #1106, #1107).** The destructive guard now registers on two surfaces. A NEW
  plugin-level `hooks/hooks.json` PreToolUse hook runs `destructive_guard.py --mode engine-gate`
  with `${user_config.disk_hygiene_enabled}` and `${CLAUDE_PLUGIN_DATA}` substituted in exec form
  (both channels docs-verified) — so a configured `false` (audit-only mode) is guard-enforced
  against engine invocations in every session, and `--data-root` authority no longer depends on
  reconstruction from the plugin root. In engine-gate mode the guard defers instantly with no
  output for any command that does not reference the engine, so unrelated work is never taxed. The
  skill-scoped belt (deny-by-default Bash + deletion-spelling PowerShell discipline) is unchanged
  and remains scoped to active cleanup. The gate acts on parsed engine INVOCATIONS, not mentions —
  `git diff -- hygiene.py`, `rg hygiene.py`, or `echo hygiene.py` defer, a word resolving to a
  DIFFERENT existing file named `hygiene.py` (a consumer's own tool) defers, and interpreter
  options before the script (`python3 -B`) cannot slip the gate; unparsable
  marker-carrying commands fail closed into the gate (review finding on the implementation PR). GuardTests now exercise the exact channel set the shipped
  plugin-level registration receives (`run_guard_engine_gate` grid), closing the
  tests-prove-undelivered-channels gap. Trust-surface delta recorded in the README's
  plugin-acceptance security review section. Docs record the observed-vs-documented hook-lifetime
  discrepancy (session-long belt firing, producer-reported — #1105 tracks the interactive repro)
  and that PreToolUse hooks fire inside subagents. The maintainer's re-affirmation of the
  Windows-engine-execution decline (#1116) is recorded in the safety model with its reversal
  trigger.

## [0.6.5]

### Fixed

- **Manual-handoff lane: container-wide deletions now require immediate pre-execution
  re-enumeration (#1108).** An approval for a container-wide operation (`Clear-RecycleBin`,
  emptying the Trash) was bound to a prose item list that could go stale between approval and
  execution — items landing in the container after approval would be destroyed under an approval
  that predated their existence (a live near-miss in the 0.6.4 consumer audit, F2). The clean
  skill's unsupported-platform handoff now forbids container-wide deletion commands outright —
  review showed even immediate re-enumeration leaves an approval-to-execution window against a
  live container — and satisfies "empty the container" by per-item deletion under the lane's
  per-path revalidation, so unenumerated arrivals survive. Also documents that Recycle Bin / Trash reversibility is conditional: bin size caps,
  policy-disabled bins, or non-NTFS/network volumes can silently make removal permanent.
  `Clear-RecycleBin` added to the PowerShell guard's mutation words, and module-qualified
  deletion cmdlets (`Module\Remove-Item`, `Module\Clear-Content`, `Module\Clear-RecycleBin`) now
  match a companion pattern the word boundary's lookbehind previously rejected (review findings
  on the same PR; the guard word is defense-in-depth for attempted container ops, which the
  manual lane now forbids) — the broader F4 spelling additions
  (`.Delete(`, robocopy purge flags) remain tracked in #1111. Engine-side changed-since-scan
  gotcha now cross-references the manual lane's re-enumeration rule (closes #1108's third
  acceptance criterion in both directions).

## [0.6.4]

### Fixed

- **A non-OS volume root (e.g. a Windows Dev Drive) is no longer blanket-rejected (#984).** A
  whole-volume root was refused purely structurally — on Windows by the mount-point gate (every drive
  letter is `os.path.ismount` True), backed by a `parent == root` filesystem-root check — with no
  reasoning about the volume's purpose, blocking a legitimate non-OS volume. Root classification is
  now reasoned: an OS-managed root (the OS drive holding an existing Windows install / `Program Files`
  / `ProgramData`, or `/` holding `/bin`, `/etc`, …) is still denied, while a non-OS volume root — a
  drive root carrying only the per-volume metadata every volume has (`System Volume Information`,
  `$Recycle.Bin`) and no OS-install marker — is now a valid target. The target-level mount rejection
  is scoped to non-root mount points, so nested and bind mounts stay hard-blocked; per-entry
  mount/OS-managed/VCS/identity protections and the preview + per-tier approval gate are unchanged.
  Scan and preview share one unverified → OS-managed → non-root-mount target-check ordering. A
  now-valid non-OS volume root composes with the large-target scan gate (0.5.0): it is a known-large
  root (`large_scan_reasons` reason `non-os-volume-root`), so an unbounded whole-volume walk returns
  `large-target-confirmation-required` unless bounded with `--max-depth` or confirmed with
  `--confirmed-large-scan`.

## [0.6.3]

### Fixed

- **The destructive-action guard was failing open on the bundled `clean` skill.** The
  skill-frontmatter PreToolUse hook passed `--authorized-data-root ${CLAUDE_PLUGIN_DATA}` in its
  args, but Claude Code refuses to launch a skill-scoped hook that references `${CLAUDE_PLUGIN_DATA}`
  (it is plugin-only; only `${CLAUDE_PLUGIN_ROOT}` is available to skill hooks) and treats the failed
  launch as a non-blocking error — so the guard silently never ran and `rm -rf`, engine `apply`, and
  the PowerShell deletion belt were all ungated. This recurs the fail-open shape earlier fixes
  addressed through a new vector (hook launch failure via an unsupported substitution token); the
  0.4.4 premise that "inline placeholder substitution resolves in exec-form hook args" does not hold
  for `${CLAUDE_PLUGIN_DATA}` in a skill-scoped hook.
  - The hook now passes only `--plugin-root ${CLAUDE_PLUGIN_ROOT}` — the sole substitution a skill
    hook receives — so it always launches. `destructive_guard.py` derives the authorized data root
    from the plugin root using Claude Code's documented persistent-data-directory layout
    (`<plugins>/data/<id>`, `<id>` = the sanitized `<name>@<marketplace>`). Every failure mode is
    fail-closed: an unrecognized layout yields no authority, so `--data-root` engine calls are denied
    while the destructive-action guard stays fully active. A direct `--authorized-data-root` and the
    `CLAUDE_PLUGIN_DATA` environment variable remain accepted as additional/fallback channels for
    hosts that can supply them.
  - **Known limitation (platform gap):** the `disk_hygiene_enabled` kill switch can no longer reach
    the guard on a skill-frontmatter hook. Its only channels are the `--disk-hygiene-enabled` argv
    flag (which needs the `${user_config.*}` substitution skill hooks do not receive) and the
    `CLAUDE_PLUGIN_OPTION_DISK_HYGIENE_ENABLED` environment variable (which the runtime does not
    inject into skill hooks). The guard therefore defaults to enabled and cannot honor a configured
    `false` by denying outright; it still forces a human prompt before every mutation, and the skill
    body's substituted value lets the model self-enforce audit-only. This never functioned on 0.4.6
    either (the hook did not launch at all), so it is a documented gap rather than a regression.
    Delivering the kill switch to a skill-scoped guard needs a channel skill hooks do not yet have.
    (#983)

## [0.6.2]

### Fixed

- **Windows platform posture no longer reads as if the engine deletes there.** `setup check`'s
  platform-posture step said "Windows (full, `lstat` reparse + Win32, never UAC)", but "full"
  described only the audit lane — `clean`'s preview returns `execution-platform-unsupported` on
  Windows and removal is a manual Recycle-Bin handoff. The posture line (and the README's Windows
  bullet) now keeps the lanes visibly separate: full **audit**; engine **execution unsupported**;
  manual, per-path Recycle-Bin handoff after explicit approval. macOS gains the matching manual
  Trash note.
- **"Skill-scoped guard" wording now says what the scope means.** The `destructive_guard.py`
  PreToolUse hook is registered in the `clean` skill's frontmatter and fires only within that
  skill's context; setup's own probes and any direct `hygiene.py` invocation rely on the engine's
  built-in containment, not the hook. One clause in `setup check` step 1 and the README
  requirements bullet now states this instead of implying always-on protection.
- **The security review's Configuration bullet no longer claims "no `userConfig`".** That claim
  has been stale since 0.3.0 introduced the `disk_hygiene_enabled` toggle; the bullet now
  describes the actual surface (one non-sensitive boolean that can only narrow the destructive
  surface) with the review conclusion unchanged.

## [0.6.1]

### Changed

- **The Python version floor now has one origin.** The "3.11+" floor was hand-maintained in at
  least five places — `hygiene.py`'s runtime check (the real enforcement), both `.test.sh`
  wrappers, both SKILL.md files, and the README — while the setup skill told itself to "probe
  what they actually require, don't recite this file"; a future bump would drift the copies
  silently. The floor is now the module-level `MIN_PYTHON` constant in `hygiene.py`: the runtime
  check and its error message derive from it, a regression test locks the constant's greppable
  line shape and proves enforcement uses it, both test wrappers parse it instead of restating
  the number (failing loudly if the parse breaks), `setup check` step 1 derives the probed floor
  from the constant, and the remaining prose mentions are annotated as pointers or convenience
  copies of that origin.

## [0.6.0]

### Added

- **Deterministic kill-switch probe** (`skills/setup/scripts/kill_switch_probe.py`): a report-only,
  stdlib-only read of the configured `disk_hygiene_enabled` value from
  `pluginConfigs[<plugin-id>].options` in the user `settings.json` (`CLAUDE_CONFIG_DIR`-aware). It
  emits one JSON line with the `effective` boolean, its `source`
  (`configured` / `default` / `indeterminate`), a `degraded` flag, and the matched entries. The
  guard's Bash allowlist now permits exactly the argument-free bundled probe invocation (any
  argument, bare `python`, or a different path stays denied).

### Fixed

- **`setup check` no longer reports the kill switch from an unexpanded body token.** Step 4
  previously emitted `${user_config.disk_hygiene_enabled}` in the skill body with the rule
  "unexpanded or empty means default `true`", so a configured `false` (audit-only mode) whose
  token failed to expand was misreported as enabled — a false-negative on the safety-critical
  setting the check exists to verify. Current plugin docs state non-sensitive `${user_config.*}`
  values substitute in skill content, but a live run observed the token unexpanded, so body-token
  expansion cannot be load-bearing for a safety report. `check` now reports the probe's
  deterministic result with provenance, degrades honestly ("could not read the configured toggle;
  assuming default `true`") when no definitive read is possible, and treats the body token as at
  most a cross-check whose contradiction is reported rather than silently resolved. The `clean`
  skill's audit-only instruction likewise stops treating an unexpanded token as "unset = enabled"
  and resolves the toggle through the same probe; enforcement remains with the guard's
  runtime-substituted `--disk-hygiene-enabled` hook argument (0.4.4).

## [0.5.0]

### Added

- **Engine-level large-target scan gate.** A `scan` whose target resolves to the user home directory
  now returns `large-target-confirmation-required` (after a cheap top-level probe, no full walk)
  unless it carries `--max-depth` or the new `--confirmed-large-scan` flag, backing the former
  prompt-only `--max-depth 1` convention with a deterministic backstop so a forgotten bound cannot
  become an accidental unbounded whole-home walk. The Bash guard accepts the valueless
  `--confirmed-large-scan` in the exact scan shape.

## [0.4.7]

### Fixed

- **The `clean` skill now hands off git worktree checkouts to `/source-control:worktree`.** An audit
  of a repos root containing worktree checkouts (e.g. under `.worktrees/`) inventories each checkout
  and protects its tracked content and `.git` metadata, but the skill named no next step for the
  worktree lifecycle it does not own. The boundary list (and the README relationship list) now point
  at `/source-control:worktree status`/`cleanup` (if installed) — run from the checkout's own main
  repository, since those actions manage the current repository's worktrees and take no target —
  extending the existing managed-state → named-handoff pattern. Discoverability only; no engine or
  safety behavior change. (#986)

## [0.4.6]

### Changed

- **Test isolation only — no runtime behavior change.** The `run_guard_powershell` helper in
  `test_hygiene.py` — the enabled-PowerShell sibling of the three helpers sealed in 0.4.5 — carried
  the identical unsealed seam: it mocked `os.environ` to drive the kill switch but left `sys.argv`
  unpatched, so an ambient `--disk-hygiene-enabled` flag in the real test-runner invocation could
  override the env-var mock the test intends to exercise. It now patches `guard.sys.argv` to a
  clean, flag-free argv alongside its existing environment mock — matching the pattern the other
  four `run_guard*` helpers use — so the environment variable stays the sole channel under test.
  This completes the seam-sealing left out of 0.4.5 for scope; standard `unittest`/`pytest`
  invocations never produced such argv, so it seals latent fragility rather than a live failure.

## [0.4.5]

### Changed

- **Test isolation only — no runtime behavior change.** The `run_guard`, `run_guard_disabled`, and
  `run_guard_powershell_disabled` helpers in `test_hygiene.py` mocked `os.environ` to exercise the
  kill switch but left `sys.argv` unpatched. Since the guard reads `--disk-hygiene-enabled` from
  `sys.argv[1:]` before the environment fallback, a test runner whose real invocation argv happened
  to carry that flag could override the env-var mock and flip an expected `deny` to `ask`. Each
  helper now patches `guard.sys.argv` to a clean, flag-free argv alongside its existing environment
  mock — matching the pattern the `run_guard_enabled_argv` helper already established — so the
  environment variable stays the sole channel under test. Standard `unittest`/`pytest` invocations
  never produced such argv, so this seals latent fragility rather than a live failure.

## [0.4.4]

### Fixed

- **The `disk_hygiene_enabled` kill switch now actually blocks deletions in audit-only mode.**
  Setting `disk_hygiene_enabled=false` (audit-only mode) failed to prevent deletions in two
  independent ways, both fixed here.
  - The PowerShell lane never consulted the kill switch: `destructive_guard.py` routed `PowerShell`
    calls to `powershell_decision` and returned before the enabled gate was computed, so flagged
    deletion spellings (`Remove-Item`, `rm`, `del`, `::Delete`, recycle-bin calls) still returned
    `ask` — and could be approved — even with execution disabled. The enabled gate is now resolved
    before the tool-name branch and threaded into `powershell_decision`, which denies flagged
    deletions in audit-only mode and only prompts (`ask`) when execution is enabled.
  - The kill switch was inert under the env-injection failure: the guard read
    `CLAUDE_PLUGIN_OPTION_DISK_HYGIENE_ENABLED` from the hook process environment and defaulted to
    enabled when absent, but the runtime does not inject plugin env vars into a skill-frontmatter
    hook's environment, so a configured `false` was silently overridden to enabled. The `clean`
    skill's hook now passes the configured value as a runtime-substituted
    `--disk-hygiene-enabled ${user_config.disk_hygiene_enabled}` argument — inline placeholder
    substitution resolves in exec-form hook `args` where environment injection does not — and the
    guard reads the kill switch from that argument, honoring the environment variable only as a
    fallback. When no channel supplies a value the guard still fails safe to enabled (guard active,
    every mutation gated behind the final human prompt). This mirrors the `--authorized-data-root`
    argv mechanism.

## [0.4.3]

### Fixed

- **The `clean` skill's destructive-safety guard now launches via a resolvable `python3`.** The
  PreToolUse hook ran in exec form via the unqualified interpreter `python`, which stock macOS and
  many Linux distros do not ship (only `python3`). Because Claude Code treats a failed hook launch
  as a non-blocking error, an unresolvable `python` fails the guard open — `rm -rf`, engine `apply`,
  and other destructive shapes stop being intercepted on the very POSIX hosts the safety model
  relies on — and a legacy `python` 2.x resolving first would crash the guard on modern syntax. The
  hook now names `python3`. A new regression test (`test_skill_hook_interpreter_is_python3_and_resolves`)
  locks the config at `python3` and probes that a runnable `python3` reports a 3.11+ interpreter.
  Enforcement remains bounded by resolution: on a host without a resolvable `python3` the launch
  still fails open on the manual PowerShell deletion lane (engine `apply` is already unsupported on
  Windows/macOS), so the per-path human approval that lane already requires and the consumer's
  baseline permission policy stay the backstop, and `/disk-hygiene:setup check` reports interpreter
  resolution. (#380)

## [0.4.2]

### Fixed

- **The `clean` skill's step 2 now defines "suspicious" for home-directory targets.** A prior
  fix covered the `tmp_*` hint-glob gap but left two findings open: an unhinted agent-session
  status file has no shared name shape to glob, and SKILL.md never said what "suspicious"
  meant for an unhinted entry. Both are the same gap: the scan snapshot already records every
  walked entry with a possibly-empty `hints` list, so the data was always there, just never
  triaged. Step 2 now instructs the model to treat any loose root-level entry at a user-home
  target that is not in `protected_exact_names` and does not match a recognizable app/config
  convention as suspicious, closing the triage gap without inventing a fabricated
  baseline-policy.json glob for a naming pattern the evidence doesn't support. (#287)

## [0.4.1]

### Fixed

- **The skill-frontmatter guard now receives its authorized data root.**
  `destructive_guard.py` read the authoritative data root only from the
  `CLAUDE_PLUGIN_DATA` environment variable, which the runtime does not inject
  into a skill-frontmatter hook's process environment. As a result `--data-root`
  never validated and the `scan`/`preview`/`apply` engine lane failed closed on
  every guarded invocation, on all platforms. The `clean` skill's hook now
  passes the root as a runtime-substituted `--authorized-data-root
  ${CLAUDE_PLUGIN_DATA}` argument — inline placeholder substitution resolves in
  hook arguments where environment injection does not — and the guard reads its
  authority from that argument, honoring `CLAUDE_PLUGIN_DATA` only as a fallback.
  The security property is unchanged: the authority is a runtime-substituted
  value the model cannot forge, validated against the model-supplied
  `--data-root`. The unsubstituted-placeholder fallback matches only the exact
  `${CLAUDE_PLUGIN_DATA}` token, so a real data-root path that merely contains
  the `${` sequence is preserved as the authority instead of being discarded.

## [0.4.0]

### Added

- **`/disk-hygiene:setup` skill on the uniform contract** (fleet conformance
  wave, dim 8). `check` reads the clean skill's bundled scripts as the source
  of truth and probes Python 3.11+, conditional Git, the current OS family's
  documented lane (Linux `lsof` and macOS audit-only reported as INFO), and
  the effective `disk_hygiene_enabled` toggle. `apply` is guidance-only with
  no write path; toggle guidance states `--config`'s fresh-install-only
  semantics. A disabled toggle downgrades prerequisite FAILs to INFO.

## [0.3.0]

Fixes driven by a live Windows user-profile audit where the engine was unusable through its
sanctioned lane and the guard's protections did not cover the platform's primary shell.

### Added

- `--data-root` on scan, preview, and apply. The Bash guard validates the value against the
  `CLAUDE_PLUGIN_DATA` its own hook process received (the runtime exports it to hook processes but
  not to shell tool subprocesses, so the engine could previously never find its generated-state
  root through the guarded lane) and discloses the authorized value in denial guidance alongside
  the interpreter path. Absent hook authority the flag fails closed; the environment variable
  remains honored as a fallback.
- `--max-depth` bounded scans. Directories at the cutoff are recorded in `truncated_paths`,
  reported as coverage gaps, and blocked from plans by a new `truncated-not-inventoried` preview
  blocker. This makes a profile-root audit possible: the previous all-or-nothing walk exceeded the
  250k entry cap on any real home directory before reaching a single loose file.
- PowerShell guard lane (matcher now `Bash|PowerShell`): engine invocations from PowerShell are
  hard-denied (Bash stays the only engine lane), and known deletion spellings / .NET Delete calls
  surface a final human permission prompt instead of executing silently. Read-only support work
  passes through untouched.
- Documented unsupported-platform manual handoff: on Windows/macOS, after the same exact-list
  human approval as the engine lane, removal proceeds manually with per-path revalidation and
  reversible (Recycle Bin / Trash) deletion preferred.
- Scan progress heartbeat to stderr every 25k entries; the entry-cap error now suggests
  `--max-depth`.
- `os_autoclean` advisory is computed before the walk and included in scan failure payloads, so a
  capped profile scan still surfaces the Storage Sense / systemd-tmpfiles recommendation.
- Baseline hints for `tmp_*` (medium ceiling) and `scratch*` (low ceiling) artifacts.

### Changed

- Generated-state error messages name the `--data-root`/`CLAUDE_PLUGIN_DATA` pair instead of the
  environment variable alone.
- **Execution kill switch migrated to native `userConfig`** (the fleet-wide kill-switch
  doctrine ruling): the `disk_hygiene_enabled` boolean (default `true`) now gates the clean
  skill's execution tiers, read by the skill-scoped guard through the native
  `CLAUDE_PLUGIN_OPTION_DISK_HYGIENE_ENABLED` hook-process mirror. Configure with
  `/plugin configure disk-hygiene` or `claude plugin install --config`.
- **BREAKING:** the `HOOK_DISK_HYGIENE_ENABLED` environment variable is retired and no
  longer read. Zero-config behavior is unchanged (execution allowed).
