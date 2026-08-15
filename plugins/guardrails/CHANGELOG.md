# Changelog

All notable changes to the `guardrails` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.28.25]

### Fixed

- **PowerShell fail-closed block messages no longer assert a git command is present
  ([#2662](https://github.com/melodic-software/claude-code-plugins/issues/2662)).**
  The sink is gated by `ps::might_invoke_git` (possibly-git), so `iex` /
  computed-call / computed-launcher paths can block with no git token. Headlines
  now say the command cannot be parsed with confidence (and, for
  `block-dangerous-git`, that it could reach git) without claiming git was found.

- **`block-hook-bypass` sources the PowerShell classifier only on PowerShell tool
  calls ([#2663](https://github.com/melodic-software/claude-code-plugins/issues/2663)).**
  `ps-command.sh` (~41 KB) is no longer parsed on every Bash PreToolUse; the
  Bash lane still sources only `hook-utils.sh` at file scope.

- **`block-dangerous-git` honors sink-shape allow-list tokens on the PowerShell
  fail-closed branch
  ([#2664](https://github.com/melodic-software/claude-code-plugins/issues/2664)).**
  Operators can narrow that sink with `ps-unparsable-dynamic-invocation`,
  `ps-unparsable-launcher`, `ps-unparsable-special-construct`, or
  `ps-unparsable-herestring-unbalanced` without the global kill switch.
  Destructive-form tokens (`reset-hard`, …) still do not open the sink.
  Allowing a sink shape blanks that opaque region and keeps checking any
  remaining visible commands — a compound like
  `Invoke-Expression '…'; git reset --hard` still requires `reset-hard`
  (Codex review on #2667).

## [0.28.24]

### Added

- **`block-windows-drive-tmp`** ([#2594](https://github.com/melodic-software/claude-code-plugins/issues/2594)):
  PreToolUse Bash|PowerShell guard that fails closed on Windows when a write target is a
  drive-root temp path — POSIX `/tmp`, MSYS `/c/tmp`, `C:\tmp`, or drive-root `\tmp` —
  which resolve to `<drive>:\tmp` instead of `%TEMP%` and accumulate at the volume root.
  Redirects and write utilities are blocked with an actionable redirect-to-`%TEMP%` /
  `$TEMP` / `$env:TEMP` message. Non-Windows hosts are untouched; `%TEMP%` / `$TEMP` /
  `$TMP` / `$TMPDIR` / `$env:TEMP` / `/var/tmp` usage is allowed. Kill switch:
  `block_windows_drive_tmp_enabled` (default on).

## [0.28.23]

### Fixed

- **Assignment without spaces (`$x=git …`) still counts as git (Claude review on #2592).** The command-position predecessor class now includes `=` so `$x=git reset --hard` (including inside `{}`/`()`) remains blocked, and the Bash hand-off strips a PowerShell `$var=` / `$var+=` prefix so the RHS command word is visible to the tokenizer.

- **Drive-relative `C:git.exe` still counts as git (Codex review on #2592).** The command-position predecessor class now includes `:` so `& 'C:git.exe' --% reset --hard` remains blocked.

- **PowerShell git probe matches `git` in command position only (#2592).**
  `ps::might_invoke_git` (and the twin probe in `ps::git_command_is_readonly`) no
  longer treats any `git` substring as an invocation. Hyphenated identifiers
  (`block-dangerous-git`, `NO-GIT`), `.git` directory names, and an intermediate
  path directory named `Git` no longer engage the fail-closed sink when paired
  with ordinary `{}`/`()` PowerShell grouping. Real `git` / `git.exe` command
  words — including path-qualified and quoted forms — still do.

## [0.28.22]

### Changed

- **Docs:** actionable `/plugin configure` guidance now uses the marketplace-qualified form
  (`<plugin>@<marketplace>`; generated option blocks use `@<marketplace>`) per
  [`docs/extensibility-contract-smoke-tests.md`](../../docs/extensibility-contract-smoke-tests.md)
  Test E (#1360). Targetless references to the flow stay unqualified.

## [0.28.21]

### Fixed

- **`block-noncanonical-commit` binds repo-context through one `repo_git_probe` chokepoint
  ([#1500](https://github.com/melodic-software/claude-code-plugins/issues/1500),
  [#1553](https://github.com/melodic-software/claude-code-plugins/issues/1553)).**
  Every git subprocess question now runs as `git -C <dir> <locating globals…> <args…>`,
  cached under `%q`-encoded keys so argv boundaries cannot collide.
  `HOOK_EFFECTIVE_LOCATING` propagates `--git-dir` / `--work-tree` / `--namespace`
  across `!` hops (cleared on pure-discovery outer hops and when an inner frame carries
  `-C`); path composition via `alias_launch_dir` / `HOOK_EFFECTIVE_BASE` stays separate
  from alias lookup. No outer fail-closed when git cannot resolve a work tree — the walk
  continues with the literal composed directory. Acceptance rows added for the #1553
  reproducer, R8-2, R8-3, and F3.

## [0.28.20]

### Fixed

- **hook-utils:** distinguish unresolved `physical_path`/`repo_root` answers and honor unquoted `#` in `bash_parse_segments` (#1487).

## [0.28.19]

### Fixed

- **`stale-path-verify` admits deleted root-level paths when the basename is
  referentially unambiguous (#1446).** Root-level inline-code tokens no longer
  require a `/` before provenance is consulted. The discriminator is explicit:
  enumerated semantically-generic root filenames (`README.md`, `package.json`,
  …) and any basename carried by more than one tracked file are still rejected;
  unambiguous names such as `CONTRIBUTING.md` or `old-config.json` now reach the
  deleted-path oracle. Widens candidate extraction only on that narrow class; a
  full-corpus re-measure against the 0.20%/50% baseline from #1432 is still
  warranted before treating the envelope as unchanged.

## [0.28.18]

### Fixed

- **hook-utils:** scope `read_file_path` to git worktrees when project dir unset (#1091).

## [0.28.16]

### Changed

- **Block-noncanonical-commit tests isolate from enclosing repo state (#2455).** Fixture
  aliases use embedded newlines so assertions exercise real block paths; hang-guard
  fallbacks skip follow-up exit checks when `timeout` reports 124.

## [0.28.15]

### Fixed

- **PowerShell fail-closed sink no longer blocks read-only git with `{}`/`()` grouping
  on commit/push guards (#1415).** `block-no-verify` passes commands like
  `git fetch | ForEach-Object { … }` when no mutating git subcommand is visible;
  obfuscated commit/push shapes still fail closed.

## [0.28.14]

### Fixed

- **`stale-path-verify` history walk uses `core.quotePath=false` and `-m` (#1452).**
  Non-ASCII deleted paths match citations literally, and deletions made while
  resolving a merge enter the deleted-path set.

## [0.28.13]

### Changed

- **Synced `hook-utils.sh`:** write `emit_telemetry`'s `data` payload to a temp file instead of passing it via `--argjson`, so payloads above the Windows command-line cap are not dropped (#1595).

## [0.28.12]

### Fixed

- **`hook::git_resolve_index` sudo cluster peel (#1811).** Peel documented valueless sudo
  short options off clustered tokens so `sudo -bD <dir> git …` records the chdir; widen the
  peel set to cover all documented valueless shorts while keeping `-h` value-taking.

## [0.28.11]

### Fixed

- **`stale-path-verify` partial-Edit reconstruction (#1455).** Lowered the token floor to two
  characters so minimal extension swaps (`md`, `js`) are not skipped, and single-word anchors now
  use word-boundary matching so a bare fragment like `docs` cannot over-recover an untouched
  citation on another line.

## [0.28.10]

### Fixed

- **`block-noncanonical-commit` replays locating globals on persisted-alias lookup (#1501).**
  `git config --get alias.<name>` now receives the invocation's `--git-dir` /
  `--work-tree` / `--namespace` sequence, matching the identity probe. A
  multi-line `-m` reached via an alias chain from outside the work tree is
  blocked instead of allowed.

## [0.28.9]

### Fixed

- **`block-noncanonical-commit`:** resolve persisted `alias.<sub>.command` subkeys, not only
  `alias.<sub>` (#1022).

## [0.28.8]

### Changed

- **Synced `hook-utils.sh`:** refuse sub-minimum `stdin_read_timeout` values (#1883).

## [0.28.7]

### Fixed

- **`strip_literals` marked non-empty dropped quote spans inside a command word as OPAQUE so
  splicing cannot manufacture a false `echo` producer (#2385).** A dropped span whose content was
  non-empty (`ec"xy"ho`) was joined without a mark, reconstructing `echo` while bash runs `ecxyho`.
  Empty dropped spans (`ec""ho`, `ec"<newline>"ho`) still splice correctly and keep blocking.
  Argument-position spans (`echo "a" x > f`) are unchanged.

## [0.28.6]

### Fixed

- **`block-dangerous-git` treats `main` and `refs/heads/main` as one ref when the command
  qualified the long form (#1418).** A dead second lease entry for an equivalent spelling no
  longer blocks a safe push whose first entry is pinned to a full object id.

## [0.28.5]

### Fixed

- **Five verdict-owning hooks now consult `HOOK_JQ_FIELDS_NUL` and refuse on a NUL byte** (#2136):
  `block-convention-violation`, `block-hook-bypass`, `block-noncanonical-commit`,
  `secret-pattern-detection`, and `hardcoded-path-check`. `block-dangerous-git` and
  `block-no-verify` already did.

## [0.28.4]

### Fixed

- **block-dangerous-git and block-no-verify fail closed on unparsable payload** (#2157).

### Changed

- **Synced `hook-utils.sh`:** `hook::jq_fields` and `hook::buffer_stdin` return 2 when jq is present but cannot parse the payload (#2157).

## [0.28.3]

### Fixed

- **`block-dangerous-git` cleared a lease when a `!` alias inherited `--git-dir` / `--work-tree`
  (#2151).** git exports those globals into a shell-alias body's environment without relocating
  its directory the way `-C` does, so the reparse's width probe ran against the payload cwd while
  the push executed in the inherited repository. Inherited locating spellings are now replayed into
  `!` reparses via `HOOK_GIT_INHERITED_LOCATING_OPTS`.

## [0.28.2]

### Fixed

- **`block-convention-violation` dropped git's own globals on a plain-alias recursion hop (#2166).**
  The alias argv rebuild sliced through `gi` instead of `sub_idx`, so a wrapper's words survived
  but git's own `-C` / locating globals between `git` and the subcommand did not. A mid-merge
  `git -C inner qc -F -` was content-gated in the wrong repository while a direct
  `git -C inner commit -F -` was correctly exempt. The rebuild now matches
  `block-dangerous-git`'s splice (`0..sub_idx`).

## [0.28.1]

### Fixed

- **`block-hook-bypass`'s own scope message told the operator it covers `inline python3 -c only`,
  which 0.28.0 had just made false (#2217).** Both emitted notes — Bash and PowerShell — are the
  guard's contract with whoever it just blocked, so understating the enforced surface is not a
  cosmetic slip: it is the same false-account defect in the opposite direction, and it invites the
  contortion the note's own preamble warns about (an agent routing to a form it is told the guard
  cannot see). 0.28.0 widened the python lane from the literal `python3 -c` to the interpreter family
  plus a `python3 - <<PY` stdin heredoc and left both notes unchanged. Emitted now, verified by
  invoking the hook:

  ```
  Scope: only this command string is inspected — known shell file-write forms plus inline python
  code (python/python3/py/pypy with -c, or a program read from stdin as python3 - <<PY) only. POSIX
  tee pipe writes, other inline-interpreter writes (e.g. node -e, sed -i), a stdin heredoc with no -
  argument (python3 <<PY), writes inside an invoked script file or a program's own opaque code, and
  redirects produced by another program, are not seen.
  ```

  The contract test is the part that should have caught this and did not: its assertion pinned the
  literal string `inline python3 -c only`, so it kept passing while the claim went stale. It now
  pins the family, the stdin form **and** the no-dash residual, so the note cannot drift from the
  detector without a failure. Found by the automated reviewer on the 0.28.0 PR, after that PR had
  already merged. No detector behaviour changes: 0 granted → refused, 0 refused → granted.

## [0.28.0]

### Fixed

- **`block-hook-bypass` missed three inline-write forms that reach a real file, one of them a
  residual the file itself recorded as accepted (#2217).** Measured against `4c90b454` (0.27.2),
  hook invoked as a decision function on a `PreToolUse` Bash payload — `rc=2` blocked, `rc=0`
  allowed:

  ```
  rc=0 :: python -c "open('f','w').write('x')"
  rc=0 :: py -c "open('f','w').write('x')"
  rc=0 :: python3.11 -c "open('f','w').write('x')"
  rc=0 :: printf 'a<newline>b<newline>' > notes.md
  rc=0 :: python3 - <<'PY' … open('f','w').write('x') … PY
  rc=2 :: python3 -c "open('f','w').write('x')"   # the one spelling that matched
  rc=2 :: printf "a\nb\n" > notes.md              # the same write, escaped newline
  ```

  Three separate causes, all in the direction of letting a write through:

  1. **The interpreter detector was a spelling floor, not a rule.** Both lanes required the literal
     `python3` — the Bash lane's `EXEC_LC` scan and the PowerShell lane's
     `ps::might_write_via_python3` token test — so `python -c`, `py -c`, `py3 -c`, `python2 -c` and
     `python3.11 -c` ran the identical inline write unseen. The guard's own scope message advertised
     `python -c` as its example, naming the one spelling the regex did not match. The command word is
     now the python family (`py`/`python`/`pypy` plus an optional version suffix and `.exe`), still
     separator-anchored, so `notpython3`, `mypython3`, `mypy`, `spy`, `happy` and `pytest` stay
     inert. `py -3 -c` is admitted because a `-<digits>` token cannot be a script path; no other gap
     between interpreter and flag is, so `python3 build.py` and `python3 -m tool …` are still not
     blocked.

  2. **A physical newline inside a quoted span split a producer from its own redirect.** A newline
     reached with a quote still OPEN is not a separator — bash is inside a quoted word, so the text
     either side of the span is ONE word — but `strip_literals` re-emitted it, `normalize_segments`
     split there, and `producer_redirect_bypass` requires producer and redirect in one segment. The
     join is now empty rather than a newline. **Empty, not a space:** `ec"<newline>"ho x > f` is
     `echo x > f` to bash, and a space join leaves `ec ho`, which `_producer_head` does not match —
     the fix ships with that case as an assertion. Joining empty cannot manufacture a token bash does
     not also form, because an open quote is what makes the two sides one word. The kept-operand and
     backslash-newline joins are unchanged; the multi-line `--body`/`-m` prose floor is unchanged
     because a dropped span's content is dropped either way.

  3. **REOPENED ACCEPTED RESIDUAL** — a stdin heredoc (`python3 - <<PY … PY`, no `-c`) was recorded
     as uncovered and accepted in the PowerShell lane's comment. It is reopened here on new
     reachability evidence rather than treated as an oversight: this repo's own session record shows
     an agent reaching for exactly that form to patch a file
     (`.work/handoffs/20260809T082720Z-handoff-post-2008-followups.md:211`, `python - <<'PY'`), and
     widening the `-c` arm raises the pressure toward it, since a refused `python -c` write reroutes
     most naturally to the heredoc. The `-` is what makes it inline: the code sits in the command
     string the hook reads, not in an opaque script file. The acceptance comment is updated in both
     `block-hook-bypass.sh` and `lib/powershell/ps-command.sh` rather than contradicted.

  **Direction of every change: 23 granted → refused, 1 refused → granted.** Measured, not asserted:
  the new assertions were run against the PRE-change hook and the failures enumerated
  (`PASS=377 FAIL=15`, every one `expected 2, got 0`), then adversarial probes written afterwards
  specifically to hunt the other direction turned up eight more rows, now assertions as well.

  The **one** in the other direction is `foo "a<newline>" echo x > f`, and it is a false positive
  being removed rather than a new exemption. Fusing the two sides of a span back into one segment
  also puts whatever preceded the span at the segment start: there bash's command word is `foo` and
  `echo` is one of its *arguments*, so the redirect's producer is another program and this guard is
  producer-scoped by design. The newline previously split it into a bogus `echo x > f` segment. The
  single-line spelling `foo "a" echo x > f` was already allowed, so this makes the multi-line form
  agree with shipped behaviour; both are asserted, as is the mirror case (`echo "a<newline>" x > f`,
  where the command word really is the producer) which moves the other way.

  It is one row and not a class, verified rather than reasoned: every command PREFIX the file already
  models — env assignments, `env`, `if…then`, `!`, `exec -a NAME`, a leading redirect — was probed in
  front of a multi-line span against both hooks, and all still block, because `_cmd_prefix` /
  `_modifier_opt_arg` / `_leading_redir` peel on the fused segment. Each is pinned with its
  single-line control. Every remaining floor keeps its `rc=0`: the name anchor, the `#1601`/`#2148`
  over-block repros re-run for each new spelling, the multi-line prose/`--body` floor, the
  `/dev/null` discard floor, and the stdin floor.

  **Accepted residual, restated at its narrowed width:** `python3 <<PY … PY` — stdin with **no** `-`
  argument — stays uncovered. Matching a bare trailing interpreter token would flip
  `echo "pathlib" | python3` and `cat script.py | python3` to blocked, so that exemption costs this
  one spelling; both floors are asserted. Same discipline as the `-c` arm: no gap is allowed between
  the interpreter and its flag beyond a `-<digits>` version selector, so `python3 -O - <<PY` is
  uncovered too — admitting an arbitrary option-shaped token is what would let a *script path*
  through as one. Inline writes via other interpreters (`node -e`, `perl -e`, `ruby -e`, `sed -i`)
  remain out of scope, unchanged.

## [0.27.2]

### Fixed

- **`skill-reference-verify` and `stale-path-verify` treated a malformed `replace_all`
  extraction like a legitimate `false` (#2126).** Both hooks now accept only the
  stringified `"true"` / `"false"` values the jq filter produces; any other shape skips
  verification rather than proceeding on the permissive branch.

### Changed

- **Eight prose references still named 0.26.0 as the release that made `block-hook-bypass`'s
  exemptions operand-keyed. It is 0.27.0.** No behaviour changes, no assertions moved. The #2226 work
  was written against 0.26.0 and renumbered when `main` took that version for the
  `block-dangerous-git` / `block-no-verify` `jq` fail-closed change (#2146) while the branch was
  open. The renumber reached the CHANGELOG heading, the manifest version and the entry's own
  comparison table; it did not reach the narrative around them, so the README caveat paragraph (2),
  the note above `scratch_target_exempt` (1), three comments in the contract test, and the erratum
  inside the 0.25.1 entry (2) each pointed a reader at a release that documents something else
  entirely. 0.26.0's own heading and entry are untouched — that is the one 0.26.0 reference in this
  plugin that is correct.

## [0.27.1]

### Fixed

- **`stale-path-verify.test.sh` comment now matches the shipped `[Ss]` exemption.** The
  assume-unchanged case comment claimed only uppercase `S` was exempt; the hook and the test
  nine lines below both treat lowercase `s` as skip-worktree too. (#1555)

## [0.27.0]

### Fixed

- **`block-hook-bypass` exempted a quoted redirect target on its first word, so a write whose real
  destination was somewhere else entirely was waved through as a `/dev/null` discard (#2226).**
  A quoted redirect operand is ONE pathname to bash. This guard decided its target-based exemptions
  on the operand's first whitespace- or separator-delimited fragment, because the machinery either
  side of that decision disagreed about what a kept operand is: `strip_literals` **keeps** a quoted
  write target as literal content — dropping the quotes so a quoted target still reads as a write —
  while `normalize_segments` then read a `;`, `|`, `&`, `(`, `)` or newline *inside* it as a segment
  boundary and `_redir_scan`'s target class ended at whitespace.

  Measured at `56f5cd21` (0.25.3), hook invoked as a decision function on a `PreToolUse` Bash
  payload — `rc=2` blocked, `rc=0` allowed:

  ```
  rc=0 :: echo x > "/dev/null ../../etc/pw"        # exempted on the word /dev/null
  rc=0 :: echo x > "/dev/null;/../../etc/passwd"
  rc=0 :: echo x > '/dev/null ../../etc/pw'
  rc=0 :: echo x > /dev/"null ../../etc/pw"
  rc=0 :: echo x > /dev/null\;/../../etc/passwd    # the unquoted escaped spelling
  rc=0 :: cat > "/dev/null ../../etc/pw"           # and the cat lane
  ```

  Nothing named `/dev/null` is the destination in any of them. Reaching a *chosen* file this way
  needs a directory whose name ends in the whitespace-bearing fragment to already exist, so this is
  correctness and defence-in-depth rather than a demonstrated escape — but it is the exact assumption
  every target-based exemption rests on, and this guard now has two.

  `strip_literals` marks a kept operand's literal content with two sentinels. `\x03` **OPAQUE**
  stands in for one character whose literal value would read as syntax downstream, or for a backslash
  escape this strip cannot reproduce faithfully (inside double quotes bash *retains* the backslash
  unless it escapes `$`, `` ` ``, `"`, `\` or a newline). It is inert to every scan, so the operand
  survives as one token, and its presence means the pathname is not recoverable here — no exemption
  of any kind may be granted. `\x04` **QUOTED** is emitted where a kept span opens; the discard
  compare strips it, so `> "/dev/null"` is still a discard, while the scratch-root axis keeps its
  shipped floor of never exempting a quoted operand. A raw `\x01`-`\x04` byte arriving in the command
  text is mapped to OPAQUE, so a forged sentinel can only ever *cost* an exemption.

  Every mark is gated on "this word began right after a `>`" — the same test the quoted-operand keep
  already used, now factored out and applied to the unquoted backslash branch too. **That gating is
  load-bearing, not tidiness:** `normalize_segments`, `_producer_head`, `_cat_redir` and every
  whitespace trim in the file are byte-for-byte as shipped, so an escaped separator *between*
  commands (`echo x \; > f`) still travels the unchanged `\x02`-to-space path, and a backslash in a
  command word (`/c/Python313/python3.exe -c`) is untouched. #1680 and #1667 read this same
  normalization; their shapes (`echo x >&2`, `printf … >&2`, `echo x &>file`, `1>&2`, `2>&1`,
  `>&2>file`, `cat 1>&2`, `cat 1>&-`) carry no quotes and no backslashes, emit no mark, and were
  measured before and after with **no delta**. Neither issue moves.

### Changed

- **The scratch-root exemption's fail-close is keyed on the redirect operand instead of the whole
  raw command, retiring both blunt edges 0.25.1 documented (#2236).** With the operand/quote
  association restored above, `scratch_target_exempt` no longer has to infer it from
  `${COMMAND#*>}`. It reads the operand's own marks, so the two frictions 0.25.1 recorded as
  unfixable-without-#2226 are gone:

  | command, root `/tmp/scratch` | 0.25.3 | 0.27.0 |
  | --- | --- | --- |
  | `echo x > /tmp/scratch/f && grep foo "notes.txt"` | blocked | **allowed** |
  | `echo x > /tmp/scratch/f; cat "notes.txt"` | blocked | **allowed** |
  | `echo "a > b" > /tmp/scratch/f` | blocked | **allowed** |
  | `echo 'x > y' > /tmp/scratch/f` | blocked | **allowed** |
  | `echo x > "/tmp/scratch/f"` — a merely quoted operand | blocked | blocked |
  | `echo x > "/tmp/scratch/a;/../../etc/passwd"` | blocked | blocked |

  **Grade every verdict this release moves on the direction that matters:** refusing an exemption is
  friction, granting one is a bypass. Counted from the new suite run against 0.25.3's hook, which
  reports 19 failures split 15/4 by direction:

  - **15 move from GRANTED to REFUSED.** The `/dev/null` family above in its quoted, single-quoted,
    partially-quoted, escaped, fd-numbered (`1>`), `cat`-lane and real-file-then-operand spellings,
    plus a multi-line quoted operand, an operand continued by a backslash-newline, and an empty
    quoted target (`> ""`).
  - **4 move from REFUSED to GRANTED** — the first four rows of the table above. That is the entire
    grant surface of this release, and each one lands on a target the marks *prove* was bare: no
    quote mark, no opaque mark, no backslash.

  A forged sentinel byte and an escaped-space operand are **not** in either set: both already blocked
  at 0.25.3 and are pinned here as regression guards, not flips. The scratch axis's own floor is
  deliberately *not* widened even though the operand is now known precisely: a quoted operand stays
  non-exempt, and 0.25.0's assertion saying so is untouched.

  0.25.1's entry below says the breadth "stays" and that narrowing it needs #2226. Both were true
  when written; #2226 is now fixed and this entry is that entry's erratum. Per Keep a Changelog the
  0.25.x entries are left as they shipped.

  One assertion 0.25.0 shipped is **retired** rather than kept: `control: /dev/null still shows the
  inherited truncation (#2226, allowed)`, which 0.25.0's own PR wrote so that it "flips visibly when
  this issue is fixed". It is replaced by six `/dev/null` assertions covering the whole family, not
  just its `;` spelling. Every other 0.25.0 and 0.25.1 assertion still passes unmodified except the
  four graded above.

## [0.26.1]

### Fixed

- **`block-dangerous-git` `repo_oid_width` no longer caches a width-0 failure or misdiagnoses it as a movable lease (#2227).** When `git rev-parse --show-object-format` fails, the guard now surfaces the git error, refuses to cache the failure for the rest of the invocation, and blocks with a distinct message from the abbreviation/wrong-width case — so a literal full-width SHA is not blamed on the operator when the repository's hash format could not be read.
- **`--no-force-with-lease` now clears unknown-width lease state.** A trailing negation that cancels every preceding `--force-with-lease` also resets `lease_width_unknown` and `_lease_oid_width_unknown`, so a pinned lease whose width probe failed is not incorrectly blocked after the negation.

## [0.26.0]

### Changed

- **`block-dangerous-git` and `block-no-verify` now FAIL CLOSED when `jq` is missing (#2146).**
  `hook::require_jq` skipped the whole hook and exited 0 after one notice per session, so on a
  machine without `jq` the guard was off: measured, `git push --force origin main` was **allowed**.
  The same two scripts already fail *closed* on the other input they cannot parse — a command above
  `MAX_COMMAND_LEN` is treated as obfuscation and blocked — so one script held two opposite postures
  toward "I cannot read this input", and an author who could not fit a dangerous command under
  16384 characters could simply be somewhere without `jq`. These two now deny instead, naming `jq`
  as the missing prerequisite and pointing at the same install route the skip notice used.
- **BREAKING for a `jq`-less machine, and stated plainly:** these guards run on every Bash and
  PowerShell tool call, and without `jq` they cannot read the command at all — so they cannot tell a
  dangerous one from a safe one and deny **both**. Every matched tool call is blocked until `jq` is
  installed or the guard's own `block_dangerous_git_enabled` / `block_no_verify_enabled` option is
  set to false. That is the hard dependency the fail-closed decision accepted; a `jq`-free substring
  pre-check was considered and rejected for manufacturing a false sense of coverage. The kill switch
  still bypasses the guard on a `jq`-less machine — `hook::check_enabled` runs before the gate.
- **Every other guardrails hook is unchanged and still fails OPEN.** Membership in the fail-closed
  class is mechanical, not a taste judgement about severity: a hook qualifies iff it *already* fails
  closed on another unparsable-input condition (today, a `MAX_COMMAND_LEN` ceiling). Exactly two do.
  `block-hook-bypass` and `block-noncanonical-commit` were considered and deliberately left
  fail-open — they guard a reversible file write or a message shape, and neither holds the internal
  contradiction. New `require-jq-posture.test.sh` pins the membership so the class cannot drift, and
  measures the four-cell ALLOW/DENY grid with `jq` genuinely unreachable (hidden by overriding the
  *lookup*, never by touching `PATH`, which would also remove `git` and produce the same answer for
  an unrelated reason), with the `jq`-present column as the discrimination control and an advisory
  hook as the posture control.

## [0.25.3]

### Fixed

- **`skill-reference-verify` reported an untouched, pre-existing reference when an Edit carried
  `replace_all: true`.** Partial-edit reconstruction separates an occurrence the call wrote from a
  coincidental one by requiring the anchor to occur exactly once — and `replace_all` is precisely
  where that rule is suspended, because there every occurrence is supposed to be the edit's own
  footprint. It is not: after `ghost` replaces `setup` everywhere, the `ghost` inside a pre-existing
  `ghost-old` matches the anchor too, and the guard named a reference the call never touched.

  The issue this closes proposed it might be unfixable, on the ground that nothing in the payload
  separates the two. That holds for `tool_input` and fails for `tool_response`, which carries the
  Edit tool's structured output: `structuredPatch` marks the lines the call actually wrote with a
  leading `+`. Under `replace_all` only, an occurrence is now kept just when its physical line is
  one the patch reports as written. The suspended uniqueness rule gets an external witness instead
  of nothing.

  Both halves of that were confirmed against pages fetched 2026-08-10 rather than recall:
  `PostToolUse` input carries `tool_response`, "the result it returned", and that field is "the
  tool's structured `Output` object" ([Hooks reference](https://code.claude.com/docs/en/hooks));
  `Output` for Edit is `FileEditOutput`, whose `structuredPatch` is `Array<{oldStart, oldLines,
  newStart, newLines, lines: string[]}>` ([Agent SDK TypeScript
  reference](https://code.claude.com/docs/en/agent-sdk/typescript), "Edit").

  Matched by line TEXT, not line number, for two reasons: numbers are wrong the moment another
  PostToolUse hook reformats the file between the write and this read — the case the reconstruction
  fallback already exists for — and mapping a character offset back to a line number costs a
  whole-prefix scan per occurrence, reintroducing the quadratic term 0.21.0 removed. The residual
  imprecision runs in the safe direction: an untouched line whose text duplicates an edited one is
  kept, and two references sharing one physical line stand or fall together.

  Gate 3 may only ever REMOVE an occurrence when it can positively identify at least one the call
  wrote. Found in review: comparing the on-disk line to the patch's line verbatim undid the
  reformatting tolerance the per-line fallback exists to provide. An earlier-ordered PostToolUse hook
  that reflows whitespace leaves the anchor locatable — a literal substring search does not care what
  surrounds it — while changing the physical line, so a genuinely written reference was silently
  dropped. Two corrections: comparison is whitespace-normalized, covering the reflow formatters
  actually perform; and if the witness recognizes no occurrence at all it **abstains**, leaving the
  unfiltered set, because a witness matching nothing is stale rather than discriminating. Without the
  abstain, a formatter that rewrote more than spacing turned this gate from a filter into a silent
  mute. Both residuals now run in the same direction: over-reporting, never under-reporting.

  Deliberately inert outside its one case. A multi-line `new_string` is not filtered — its anchor
  extent spans several lines, matches no single patch line, and filtering would erase every finding
  rather than narrow them. A payload with no `tool_response`, and every non-`replace_all` Edit,
  behaves exactly as before. Field supply is **observed, not merely documented**: an independent
  reviewer captured a live PostToolUse payload on `claude 2.1.225`, in which `tool_response` arrives
  as an object carrying `structuredPatch` (complete, not truncated, at 42 replacement sites in a
  300-line file). The read is shape-tolerant regardless — a non-object `tool_response` yields an
  empty witness and leaves the filter inert, rather than erroring the payload parse and silencing the
  whole guard.

  Scope worth stating plainly, since it is broader than "fixes one false positive": under
  `replace_all`, a genuine reference sitting on a line the patch reports as CONTEXT is no longer
  reported. That is the gate working as designed — a context line is one the call did not write — but
  it does narrow what this guard says about a `replace_all` edit.

## [0.25.2]

### Fixed

- **`block-convention-violation` read the wrong repository's git config, so a commit whose
  subject violates the team convention passed unblocked.** Its `effective_dir` scanned EVERY word of
  the command for `-C` — no `[git, subcommand)` slice and no wrapper replay, the shape the shared
  parser from #1785 replaced, and that #2100 removed from `block-dangerous-git`. It failed
  in the opposite direction from that sibling: not blind to a chdir, but inventing chdirs that were
  never there. In `env -u -C git <alias> …`, GNU env's `-u NAME` consumes `-C` as the variable to
  unset, so git never moves — yet the every-word scan composed `<cwd>/git` and looked for the alias
  there. The consumer that matters is the gitconfig alias lookup, which has neither a stdin-form
  gate nor an exemption gate and fails OPEN: reading the wrong repository's config silently misses
  the expansion, the guard never learns the real subcommand is `commit`, and the convention goes
  unenforced. `effective_dir` now takes git's own globals only — the slice from the resolved git
  token to the subcommand — preceded by any genuine wrapper chdir replayed from
  `HOOK_GIT_RESOLVED_WRAPPER_DIRS`, which is the one parser that can tell a real `env -C <dir>`
  from the `-C` in `env -u -C git`. The sequencer probe at the same call site is corrected with it.

  A post-subcommand `-C` is `--reuse-message`, not a directory, and the distinction is purely
  positional. Note that `git commit -C HEAD` cannot itself demonstrate this: `-C` sets the
  reuse-message exemption and the hook returns before `effective_dir` is ever called, so that
  invocation answered "allowed" both before and after and would read as already fixed. The
  positional case is covered through the alias lookup instead, where no exemption applies.

  **Acceptance behavior changes** (hence a minor bump): a wrapped alias invocation whose expansion
  is `commit` is now content-gated where it was waved through, and one whose alias exists only in
  an unrelated directory the scan used to compose is no longer blocked on an expansion git would
  never perform.

- **A `!` shell alias lost the directory its invocation resolved to, so a prepared merge commit was
  blocked instead of exempted.** Found in review of the above. A `!` alias body re-parses as a NEW
  top-level command, and that fresh argv carries neither the wrapper that moved git nor git's own
  globals — so `env -C <dir> git <alias>` resolved the alias in `<dir>` and then evaluated the alias
  body's sequencer probe against the payload cwd. With a merge in progress in `<dir>`, the commit
  git was about to make carries a prepared message and the guard documents an exemption for exactly
  that; it was gated instead. `effective_dir` now falls back to `HOOK_EFFECTIVE_BASE`, which the
  caller sets to the resolved directory around each `!` reparse and restores after — the mechanism
  `block-noncanonical-commit.sh` already uses. Pre-existing, not introduced by the scoping fix above;
  the fix simply made the path reachable enough to demonstrate.

  What this composes is the caller's directory, where the sibling asks git for the alias's real
  launch directory (git starts a `!` body at the work tree's top level). For this guard's two
  consumers the two agree — `config --get` and `rev-parse --absolute-git-dir` answer identically from
  anywhere inside one repository. They diverge only when a separate repository is nested below the
  composed path, which is deliberately not modelled here.

## [0.25.1]

### Changed

> **Erratum:** the second bullet below states that the fail-close's breadth stays, because narrowing
> it needs #2226. #2226 is fixed in 0.26.0 and the breadth is gone — the check is keyed on the
> redirect operand now. The mechanism this entry corrects for 0.25.0 was accurate for 0.25.x; see
> 0.26.0 above for what replaced it. Everything else in this entry is unchanged.

- **`block-hook-bypass`'s scope note now names `tee` and other inline-interpreter
  write families it does not model (#2218).** No behaviour changes — lane-specific
  `_BYPASS_SCOPE_NOTE_BASH` / `_BYPASS_SCOPE_NOTE_PWSH`, two `SCOPE (documented
  residual)` blocks, the README residuals section, and five accepted-floor tests
  now move together so a reader does not credit the guard with POSIX `tee` or
  general interpreter coverage from the old "recognized inline interpreter code"
  wording — and a PowerShell block no longer claims `tee` is unseen when Tee-Object
  and its alias are modeled.

- **0.25.0 described the scratch-root exemption's fail-close inaccurately on every surface, twice
  over. Corrected, and pinned (#2236; root cause #2226).** No behaviour changes — four documents
  become accurate and four regression tests now pin the boundaries they describe.

  0.25.0 said the exemption fails closed on "a quoted or escaped **operand**", "after the first
  redirect **operator**". Both halves are wrong, in the same direction — they imply precision the
  check does not have:

  1. **It is not operand-scoped.** It reads the whole raw command tail, not the segment being
     evaluated and not the target word, so a quote in an unrelated *later* segment cancels the
     exemption for an earlier, unambiguous write.
  2. **It is not keyed on the redirect operator.** `${COMMAND#*>}` splits at the first literal `>`
     **character**, without deciding whether that `>` is an operator at all. A `>` inside quoted
     *content* therefore starts the scanned tail early, and the closing quote of that same content
     lands inside it.

  Consequence of (2), and the case 0.25.0's own text got backwards: it claimed quotes *before* the
  redirect are the ordinary case and keep the exemption. That holds only while the quoted content
  contains no `>`.

  | command, root `/tmp/scratch` | verdict |
  | --- | --- |
  | `echo x > /tmp/scratch/f` | allowed |
  | `echo "hello world" > /tmp/scratch/f` | allowed |
  | `echo x > /tmp/scratch/f && grep foo "notes.txt"` — quote in a later segment | **blocked** |
  | `echo x > /tmp/scratch/f && grep foo notes.txt` | allowed |
  | `echo "a > b" > /tmp/scratch/f` — `>` inside quoted content | **blocked** |
  | `echo 'x > y' > /tmp/scratch/f` | **blocked** |

  The breadth stays. It is one-directional — the check can only ever *refuse* an exemption, never
  grant one — so the failure mode is lost convenience, never a bypass. Keying it on the real redirect
  operator, or narrowing it to the operand, both need the same thing: knowing which `>` and which
  quotes are syntax rather than content. That is exactly the association `strip_literals` destroys
  before this code runs, which is **#2226**, not a separate fix, and it is deliberately not attempted
  here. Recorded on #2226 as further evidence.

  The hook comment, the README, the manifest's option description and this entry now state the
  mechanism as it is: **any quote or backslash after the first `>` character, operator or not,
  anywhere in the command.**

  0.25.0's entry below is left as it shipped, per Keep a Changelog; this entry is its erratum.

## [0.25.0]

### Added

> **Erratum:** the fail-close scope described in this entry is inaccurate in two ways. See 0.25.1
> above for the corrected mechanism. The behaviour described elsewhere in this entry is unchanged.

- **`block-hook-bypass` gains an opt-in scratch-root exemption, and with it its first
  target-scoped axis (#2210).** A read-only investigation that writes a throwaway probe file
  under a session or job temp root was blocked exactly like a repo-file write — reproduced twice,
  once against the reporting session and once against the validation pass that confirmed it, which
  was blocked by the installed guard while building a telemetry-sink probe under `/tmp`. None of the
  Write/Edit hooks this guard exists to protect (the nine formatters, secret-pattern detection,
  hardcoded-path checking, the three verifiers) would ever process such a file.

  **State the design change plainly, because it is one.** This guard is PRODUCER-scoped: it fires on
  `echo`/`printf`/`cat`/`python3 -c` as the command whose stdout reaches a file, wherever that file
  lives. The originating report framed a carve-out as a *tightening of the existing producer
  scoping*; it is not, and shipping that rationale would have been wrong. A carve-out by target path
  adds a new axis to the guard's design. The producer axis is untouched — an inline `python3 -c`
  write into an exempt root still blocks, and a test pins that.

  The new `block_hook_bypass_scratch_roots` option takes a comma-separated list of absolute
  directories and **defaults to empty, so no shipped behaviour changes**. Two tests assert exactly
  that: a temp write still blocks with the option unset, and again with it set empty. The reported
  friction therefore persists until an operator names their own roots — deliberately, because the
  last target-based exemption of this shape (`/dev/null`) shipped a one-token bypass of the whole
  guard (write the discard first, the real file second), and the default trust surface stays
  byte-for-byte what it was.

  The match is made against a lexically normalized path, never a substring or a bare prefix compare.
  Windows separators and drive letters fold to the Git Bash spelling — so a root configured as
  `D:\jobtmp\scratch` covers a target written `/d/jobtmp/scratch/f` — `.` and `..` resolve by
  component, and containment requires the target to continue with `/` past the root's last
  component. (A backslash-spelled *target* is a separate matter and is never exempt: in bash a
  backslash is an escape, so it is not the path it looks like. See the fail-close below.) The
  adversarial floor is the point of the test block, not the happy path:

  | shape | verdict |
  | --- | --- |
  | `echo x > /tmp/scratch/f`, root `/tmp/scratch` | allowed |
  | `echo x > /tmp/scratchevil/f`, same root (a string prefix would exempt it) | **blocked** |
  | `echo x > /tmp/scratch` — the root itself; containment is strict | **blocked** |
  | `echo x > /tmp/scratch/../../etc/passwd` | **blocked** |
  | `echo x > /tmp/scratch/f > real.txt` — the effective-target rule the `/dev/null` exemption already survived | **blocked** |
  | `echo a > /tmp/scratch/f && echo b > real.txt` — an exemption cannot leak across segments | **blocked** |
  | a relative, `$VAR`, `~` or glob target | **blocked** |
  | `python3 -c "open('/tmp/scratch/x','w').write('a')"` — producer axis unchanged | **blocked** |

  **A quoted or escaped redirect operand is never exempt.** This was caught in review and is the
  sharpest edge on the whole axis. `strip_literals` keeps a quoted write target but **drops its
  quotes**, and `normalize_segments` then resolves a `;`, `|`, `&`, newline or space *inside that
  operand* as syntax — so `echo x > "/tmp/scratch/a;/../../etc/passwd"`, which bash treats as one
  pathname, reaches the containment check as the safe-looking prefix `/tmp/scratch/a`. Exempting
  that prefix would be precisely the one-token bypass the `/dev/null` precedent warns about. The
  only surviving evidence of the truncation is the raw command, so the exemption **fails closed on
  any quote or backslash after the first redirect operator**. Deliberately conservative: even a
  benign `> "/tmp/scratch/f"` loses the exemption, and an operator who wants it writes the target
  unquoted. Quotes *before* the operator (`echo "hello world" > /tmp/scratch/f`) are the ordinary
  case and keep it. Six tests pin the closed shapes.

  The same truncation reaches the **`/dev/null`** exemption and **predates this change** — measured
  at `685dd381`, `echo x > "/dev/null;/../../etc/passwd"` is already allowed there. Fixing that half
  means teaching `strip_literals` to mark a kept operand's internal separators, shared machinery
  #1680 and #1667 also concern and wider than this row, so it is filed as **#2226** and pinned here
  by a control test that flips visibly when it is fixed.

  Two further residuals, both deliberate, both stated in the file and the README, both pinned.
  Normalization is lexical, not filesystem resolution: symlinks are not followed, because resolving
  them needs a subprocess per segment on a path this file deliberately keeps fork-free, and the
  target frequently does not exist yet — naming a root is accepting that root's contents. And the
  compare is case-insensitive, because the segment scan runs over the lowercased command; on a
  case-sensitive filesystem a sibling differing from a root only in case is also exempt.

  Bash lane only. The PowerShell lane classifies on cmdlet/redirect co-occurrence and never resolves
  a single effective target, so there is no well-defined target to exempt there; its `$null` discard
  is unchanged.

## [0.24.3]

### Changed

- **Carries the shared hook library's new `hook::is_enabled` predicate.** `hook::check_enabled`
  exits the process when a plugin is gated off, which is correct for a hook but wrong for a
  caller that must keep running afterward. The resolution is now also available as a predicate
  that returns instead of exiting. No behaviour of this plugin changes; the version moves so
  consumers receive the updated library.

## [0.24.2]

### Changed

- **Upstream doc stamps re-verified against the live pages (2026-08-10).** Each dated claim below was re-checked against the complete raw markdown source of the page it cites (`https://code.claude.com/docs/en/<page>.md`), not a summarized fetch, and each was confirmed by a verbatim quote before its stamp was refreshed. No claim changed; only the verification dates moved.

  - `hooks/skill-reference-verify.sh` — the manifest `skills` key adding to rather than replacing
    the default `skills/` scan, the marketplace-root exception the hook deliberately does not
    model, `.`/`./` both denoting the plugin root, and the root-`SKILL.md` single-skill
    auto-load condition (plugins reference, "Path behavior rules").

## [0.24.1]

### Fixed

- **`block-no-verify` and `block-dangerous-git` still allowed a NUL-bearing command after
  0.23.1 (#2122).** 0.23.1 stopped the helper's cardinality failure by stripping every NUL out of
  each value, which closed the fail-open for the content guards. It did not close the command
  guards: stripping SPLICES the bytes on either side of the NUL into one token the payload never
  carried contiguously, and the guards then match against that token. Measured at the hook boundary
  on the shipped hooks, `origin/main` at `fd075c27` versus this change, identical fixtures whose NUL
  is a real byte decoded from a JSON `\u0000` escape:

  | payload | main | this change |
  | --- | --- | --- |
  | `git commit --no-verify<NUL>x` | **0 allowed** | **2 blocked** |
  | `git push --force<NUL>x` | **0 allowed** | **2 blocked** |
  | a lone NUL, and a trailing NUL | **0 allowed** | **2 blocked** |
  | `git commit --no-veri<NUL>fy` | 2 blocked | 2 blocked |
  | clean `--no-verify` / clean `--force` / harmless | 2 / 2 / 0 | 2 / 2 / 0 |

  The last two rows are stated rather than counted: the splice happens to reassemble a real
  `--no-verify` in the fourth row, so `main` already blocks it and it evidences nothing, and no
  clean command changed verdict in either direction.

- **Both guards now fail CLOSED on a NUL byte in any field they read.** The new
  `HOOK_JQ_FIELDS_NUL` global reports the byte, and both guards block on it — ahead of their
  empty-command skip, so a command consisting only of NUL bytes, which strips to nothing, cannot
  pass as "no command". They refuse rather than match because the text a guard can read is not
  dependably the text that would run: bash **discards** a NUL while parsing a command it reads,
  Node's `child_process` **refuses** a NUL-bearing string outright, and which of them (if either) a
  hook payload reaches has not been traced. Refusing is correct under all of them and needs no such
  trace. Synced from `lib/hook-utils.sh`.

- **A non-zero return from `hook::jq_fields` still means the guards allow, and that is unchanged.**
  jq being absent, a malformed payload, a wrongly typed field, two concatenated JSON documents, or
  an empty buffer all still reach it, and every caller spells it `|| exit 0`. That path is out of
  scope here and is documented rather than claimed away.

## [0.24.0]

### Fixed

- **`block-dangerous-git` no longer clears an unsafe `--force-with-lease` by measuring the wrong
  repository (#2124).** The lease check accepts a `=<refname>:<expect>` whose `<expect>` is a
  full-width object id, because git cannot resolve one to something newer at push time. The width
  is the local repository's, and the guard probed the HOOK PROCESS's directory to learn it. Claude
  Code launches hooks from the session root and runs the Bash tool wherever the session stands, so
  the two differ routinely — and a payload `cwd` in a SHA-256 repository with the hook process in a
  SHA-1 one read a 40-hex lease as an immutable object id while git resolves it as a movable REF
  NAME where the push actually runs. That is precisely the hole `--force-with-lease` exists to
  close, and it needed no wrapper and no `cd`: a plain `git push` was enough. The payload's `.cwd`
  is now read and replayed as a LEADING `-C` ahead of any wrapper chdir, so it composes under git's
  own rules exactly as the wrapper replay already did. The base-resolution chain is
  `HOOK_EFFECTIVE_BASE` → `HOOK_CWD` → `CLAUDE_PROJECT_DIR` → `.`, adopted verbatim from
  `block-noncanonical-commit` rather than invented a second time; a `!` shell alias relocates the
  base for its reparse and it is save/restored around each one, since git launches that body in the
  relocated repository.
- **The alias re-expansion memo keys on the effective base, so a cached verdict cannot be reused
  across repositories (#2124).** Caught in review of this change, and a defect this change itself
  introduced: making the lease verdict a function of the base means the base has to be part of any
  key that memoizes that verdict, and `HOOK_ALIAS_MEMO` keyed only on kind, seen-set and command
  text. One Bash command invoking the SAME `!` alias text twice — first under a SHA-1 `git -C`,
  where a 40-hex expectation is a real object id and is correctly allowed, then under a SHA-256
  `git -C`, where the identical word is a movable ref name — had its second analysis skipped as
  already seen, and the guard exited 0. Verified against this branch's own pre-fix head rather than
  `origin/main`, which has no base-dependent verdict to cache wrongly: the buggy tree runs the width
  probe ONCE (`40`) and allows; the fixed tree runs it twice (`40`, then `64`) and blocks. The
  other cache, `repo_oid_width`, was checked for the same class and is already base-keyed — its key
  is the replayed option list, which now leads with the base — confirmed empirically, not by
  inspection. `block-noncanonical-commit` keys its memo on the base for exactly this reason.

  The collision was unconditional rather than occasional: the `!` branch empties `HOOK_ALIAS_SEEN`
  *before* the key is built, so the old key reduced to kind + a constant + the reparse text, and two
  reparses of identical alias text collided at any depth, through `;` and `&&` alike. It could only
  ever be a bypass, never a false block — a memo hit skips analysis, skipping can only turn DENY
  into ALLOW, and the guard exits at the first blocking segment so nothing follows a DENY.

  **Cost, measured.** Keying on the base means the memo dedups less, so analyses now scale with the
  number of DISTINCT bases in one command instead of collapsing to one. Counted from the `bash -x`
  trace, distinct bases → analyses (width probes): old 1→1 (2), 4→1 (2), 16→1 (2), 32→1 (2); new
  1→1 (2), 4→4 (8), 16→16 (32), 32→32 (64). Linear, and that collapse to 1 was the defect, not an
  optimization worth keeping. `HOOK_ALIAS_WORK_MAX` (128) still bounds it and exhausting it fails
  CLOSED, so the weakened dedup costs work, never safety. A fixture pins 16 distinct bases as
  allowed-and-bounded, and the same walk with a SHA-256 base appended as still blocked.

  Two things the reviewer flagged as reasoned-not-run are now run. The memo does not survive a hook
  invocation — it is a shell variable in a process that exits, and the sha1-then-sha256 pair split
  across two separate invocations gives 0 then 2. The git-alias branch shares the memo under a
  different tag and is covered by construction, since the base is keyed inside
  `alias_reexpand_admit` rather than at the call sites; no live case is constructible there, because
  a git alias splices words into the same argv and cannot relocate the base.
- **`env -S` / `--split-string` no longer hides a whole command from the git guards (#2124).** `-S`
  exists so a shebang line can pass OPTIONS to env (`#!/usr/bin/env -S -i prog`), so the words it
  splits out are env's own arguments. `hook::git_resolve_index` spliced them back into the scan but
  resumed at the COMMAND dispatcher, which read a leading option in the split string as the command
  NAME and gave up — `env -S '-C <sha256-repo> git push --force-with-lease=main:<40-hex>'` and even
  a bare `env -S '-v git push --force'` resolved to no git at all, so the guard never examined
  them. Parsing now resumes inside env's own option loop, which also keeps env's single chdir slot
  last-wins across the splice (`env -C a -S '-C b git …'` reports `b`, as GNU env behaves). This is
  the LARGER of the two holes and it was not lease-specific: an independent adversary confirmed
  `block-no-verify` allowed `git commit --no-verify` and `block-dangerous-git` allowed
  `git reset --hard` behind the same `env -S` form. `hook::git_resolve_index` is the shared resolver,
  so the hole was shared — `hook-utils.sh` lives in 17 places (`lib/` plus 16 plugin copies) and
  every one of them was stale. Synced from `lib/hook-utils.sh`, so all 17 carry the fix.

### Changed

- **A RELATIVE `--git-dir` / `--work-tree` / `--namespace` / `-C` in a guarded command now resolves
  against the directory the TOOL CALL runs in, not the hook process's.** This falls out of the
  leading-`-C` base above and is the correct origin — a relative path written in a tool call means
  relative to where that call runs — but it is a behaviour change and is called out here so it is
  not read as a regression. An ABSOLUTE one is unaffected.
- `repo_oid_width`'s known-gap docblock is restated at its real width. It described the residual as
  needing "a SHA-256 repository, a lease pinned to a full-width hex word that is also a ref name
  there, and a compound `cd` into it" — three conjuncts, when at the time the payload cwd was not
  read at all and neither the wrapper nor the `cd` was required. Reading `.cwd` closes that route;
  what remains is any SHELL relocation the static parser does not evaluate (`cd … && git push`, a
  subshell, `pushd`), and the comment now says so plainly. A documented gap that reads narrower
  than it is, is how this one survived review.
- The known-gap docblock also now records that the gap's PRIMARY symptom is a false BLOCK, not a
  bypass: with a shell `cd` the probe measures a base that is often not a repository, answers width
  0, and fails closed — so `cd <repo> && git push --force-with-lease=main:<literal full-width sha>
  origin main`, the exact form the block message prescribes, is denied from a non-repository session
  root. Fail-closed is right for an unresolvable base; the note exists so the next person to narrow
  the gap treats the false block as the symptom to measure.
- A second residual is now documented rather than left implicit: git EXPORTS an explicit
  `--git-dir` / `--work-tree` into a `!` shell-alias body, so the body inherits a repository the
  composed directory does not name and its lease is judged against the base. Reproduced against
  BOTH `origin/main` and this change — pre-existing, of the same family, and closing it means
  replaying inherited globals rather than a directory, which is a larger mechanism than the base
  chain adopted here.

## [0.23.1]

### Fixed

- **A NUL byte in a `Write`/`Edit`/`NotebookEdit` content field no longer disables the content
  guards.** Regression introduced by the `hook::jq_fields` conversion in 0.22.1: the helper
  delimits its batched fields with NUL, and JSON may legitimately encode a NUL inside a string, so
  jq emitted the raw byte, the field count came back wrong, and `secret-pattern-detection`,
  `hardcoded-path-check`, `skill-reference-verify`, `stale-path-verify` and `cli-flag-verify` all
  took their `|| exit 0` skip — a credential or machine path placed after the NUL passed unblocked.
  Reproduced against `origin/main` (exit 2, blocked) versus 0.22.1 (exit 0, allowed). `hook::jq_fields`
  now strips NUL inside the jq filter, so the delimiter cannot collide with content and everything
  after the NUL is still scanned, matching the pre-conversion command substitution byte for byte.
  Regression cases added to `lib/hook-utils.test.sh`, `secret-pattern-detection.test.sh` and
  `hardcoded-path-check.test.sh`. Synced from `lib/hook-utils.sh`.

### Changed

- `skill-reference-verify` and `stale-path-verify` say plainly that keeping `replace_all`'s
  `// false | tostring` inside the jq filter is for parity with the pre-conversion output, not
  because a branch depends on it — every consumer tests `== "true"`, which `""` and `"false"` fail
  alike. Comment only; behavior unchanged.

- **Every remaining hook now parses its payload in ONE `jq` process (`hook::jq_fields`), not two or
  three.** #2007 introduced the helper and converted `block-dangerous-git` and `block-no-verify`; the
  other ten hooks still ran a separate `printf … | jq … | tr -d '\r'` pipeline per field over the
  same stdin envelope. Converted: `block-noncanonical-commit`, `block-convention-violation` (3 jq
  execs → 1 each), `hardcoded-path-check`, `secret-pattern-detection`, `skill-reference-verify`,
  `stale-path-verify` (3 → 1 each), `block-hook-bypass`, `flag-commit-pr-skill-bypass`,
  `cli-flag-verify`, `workflow-resilience-check` (2 → 1 each). Measured on Windows Git Bash with the
  arms interleaved in one loop and compared as paired deltas — every sample is recorded in the PR.
  Conservative headline, the least-favourable quartile (p75) of the paired deltas: **-404 ms** per
  invocation for a 3-field hook and **-194 ms** for a 2-field hook, which agrees independently with
  the least-contended floor across 100 iterations (-394 ms / -192 ms). Medians run higher because
  this host was running several agents concurrently (-1033 / -991 ms for 3 fields, -274 ms for
  2 fields; -687 ms end-to-end across a whole `block-noncanonical-commit` invocation). Direction is
  not in doubt: the converted arm was faster in 87-95% of paired iterations. No behavior change:
  every hook's contract suite passes unchanged, the `// "Bash"` tool-name default moves to the
  bash-side expansion (the `block-dangerous-git` pattern), and a jq failure still exits 0 through the
  same empty-field guard it always did.
- `hardcoded-path-check` and `secret-pattern-detection` now serialize the per-tool content field in
  the same call as the tool name, i.e. BEFORE the file-path exclusions and the `git check-ignore`
  skip that used to precede it. Deliberate: the payload is already buffered in memory, so the
  marginal cost on a skipped write is one copy out of jq, traded against one fewer process on every
  path — and process creation, not jq's parse, is what costs on this host.
- `skill-reference-verify` and `stale-path-verify` keep `replace_all`'s `// false | tostring` INSIDE
  the jq filter. `hook::jq_fields` wraps each filter in `// ""`, and jq's `//` treats the boolean
  `false` as empty — a bare `.tool_input.replace_all` would come back `""` instead of `"false"`.

## [0.23.0]

**Note on the version bump.** MINOR rather than patch, on the same test 0.22.1 applied: does the
change alter what the guard reports on? It does, in one direction. `RECONSTRUCT_MAX_CHARS` is now
read as BYTES rather than characters (see the docblock at `skill-reference-verify.sh`), so a large
multibyte file that previously fit under the character cap can now exceed the byte cap and skip
reconstruction. That is a narrowing a consumer can observe, so it does not belong in a patch
release — even though the locale pin itself is a fix and the rest of the entry is a relabel.

### Fixed

- **`skill-reference-verify`'s partial-edit reconstruction ran in the consumer's ambient locale,
  so its matcher semantics and its cost were whatever the invoking shell happened to be set to.**
  Every search the reconstruction performs is LITERAL, but bash's `%%` pattern strip DECODES
  rather than compares under a multibyte locale, so the same scan is charged roughly 6.5x for a
  decode it never uses. Measured on a lightly-loaded Windows/Git Bash host (bash 5.3, 32 logical
  cores at ~18%), one no-match scan costs 0.054 s at 32 KiB / 0.221 s at 64 KiB / 0.880 s at 128 KiB
  under `LC_ALL=C`, against 0.395 s / 1.447 s / 5.786 s under `en_US.UTF-8`. The function now pins
  `local +x LC_ALL=C` for its own scanning, which makes both its cost and its matcher independent
  of the caller. No wall-clock bound is claimed from those figures — the ratio is the finding.

  The `+x` is load-bearing rather than incidental. A plain `local LC_ALL=C` inherits the export
  attribute whenever the consumer exported `LC_ALL`, which pushes the pin into the `grep`/`sed`
  children; `[[:space:]]` admits some non-ASCII spaces under a UTF-8 locale but never under C, so
  an exported pin silently drops a reference whose argument separator is one of them. That costs
  detection and buys nothing: the entire ~6.5x is bash's own matcher, and `grep -oE` over the same
  64 KiB measured 0.139 s under BOTH locales. Un-exported, the children keep running in the
  caller's locale exactly as before — verified identical on Git Bash (Cygwin 3.6.9, bash 5.3) and
  on Linux (glibc 2.39, bash 5.2), which is what rules out a platform-specific `+x` semantic.

  WHICH non-ASCII spaces qualify is the host C library's table and is not portable: glibc dropped
  U+00A0 and U+202F from `space` in 2.26, while Cygwin/MSYS still classifies them; U+3000 and
  U+2028 are admitted by both. The regression case therefore DISCOVERS a separator the host
  actually classifies differently between the two locales instead of hardcoding one — an earlier
  revision hardcoded U+00A0, which passed on Windows and failed on Linux CI because it asserted a
  libc's classification rather than this hook's behavior. If no candidate discriminates, the case
  reports a loud, reasoned skip naming the platform rather than passing quietly.

### Changed

- **The reconstruction cost curve in `skill-reference-verify` is now labelled with the locale it
  was measured in.** The published figures (0.07 s at 32 KiB … 3.94 s at 256 KiB) match the
  C-locale column, but the hook did not then run in the C locale, so the table described a locale
  the code never used. The pin above makes C the actual locale, so the figures are re-labelled
  rather than re-measured; a re-check on a second host of the same shape read 0.054 s / 0.221 s /
  0.880 s / 3.410 s at 32 / 64 / 128 / 256 KiB.

## [0.22.1]

### Fixed

- **`secret-pattern-detection` and `hardcoded-path-check` — both BLOCKING PreToolUse guards —
  produced NO VERDICT AT ALL for a payload of 65536-65663 bytes.** Not slow: deadlocked. Bash
  delivers a here-string by filling a pipe ITSELF, before the reader is exec'd, and it appends a
  newline — so a payload in that band puts the write 1-128 bytes past the 65536-byte pipe capacity
  and blocks forever (at >=129 bytes over, bash spills to a temp file and it works again, which is
  why 65535 and 65664 always passed and only the band between them hung). Measured on Git Bash
  against the pre-fix hooks: a 65536-byte Write carrying a live-shape AWS access-key id returned
  nothing at a 200-second bound, where the same token in a small payload exits 2 immediately. Both
  hooks are registered at `timeout: 60`, so the harness cancels the guard and the verdict is lost —
  a fail-open reachable by any agent that controls the size of what it writes. Every whole-payload
  `<<<` in the plugin now feeds its reader through process substitution instead: the two pre-filter
  gates in `lib/path-detection/hardcoded-path-patterns.sh`, the fast-reject and per-pattern
  itemization in `secret-pattern-detection.sh`, and the telemetry-label grep in
  `hardcoded-path-check.sh` — the last of which is payload-sized too, because `$VIOLATIONS` embeds
  each MATCHED LINE verbatim and the lib's `head -3` bounds the line count, not the byte count, so
  one 65KB minified line carrying a hardcoded path deadlocked on the blocked path after the stderr
  message but before `exit 2`. Same class as #1587, which fixed `hook-utils.sh`'s JSON path and
  stopped there.

  `printf … | grep -q` is NOT the alternative, and the comment that previously justified the
  here-string was half right about why: `grep -q` exits at the first match and SIGPIPEs `printf`, so
  under the `set -uo pipefail` these hooks run with, the pipeline reports printf's 141 — and
  `if ! grep -q …` reads any non-zero status as "no match" and early-returns clean, inverting a
  real detection into a fail-open. Process substitution keeps the writer OUT of the pipeline, so
  `pipefail` can never see its SIGPIPE, while preserving the early exit the gate exists for.
  Verified empirically at every boundary size under `set -o pipefail`, in both the match and
  no-match directions. This also resolves a contradiction inside the plugin: the pattern lib told
  readers to PREFER a here-string over `printf | grep`, while `hook-utils.sh` told them a whole
  payload must never go through `<<<` because it blocks at the pipe capacity. The lib now states the
  same rule as `hook-utils.sh` and cites it — a pipe when the reader drains its input (`jq`), process
  substitution when the reader may exit early (`grep -q`). `hook-utils.sh` itself is left byte-identical
  to `main`: its guidance was already correct, and the sync gate would require a version bump plus a
  changelog entry for all fourteen other plugins that carry the shared lib in exchange for a
  comment-only edit.

- **The same deadlock in six command-scanning guards.** `block-convention-violation`,
  `block-hook-bypass`, `flag-commit-pr-skill-bypass`, and the shared PowerShell command lib fed the
  whole Bash/PowerShell command — or segments derived from it — through `while … done <<<"$cmd"`,
  which deadlocks identically at 65536-65663 bytes. `workflow-resilience-check` did the same with an
  inline Workflow `script:`. All now use `< <(printf '%s\n' …)`, which is byte-identical to the
  here-string it replaces (`<<<` appends a newline unconditionally) and so cannot drop a final line.

### Changed

- Boundary regression cases at 65535 / 65536 / 65600 / 65663 / 65664 bytes in both
  `secret-pattern-detection.test.sh` and `hardcoded-path-check.test.sh`, including payloads where a
  real detectable secret / hardcoded path sits INSIDE the hang window and must still exit 2. Neither
  suite previously had a single payload-size case. Every case is bounded by `timeout` and asserts
  the EXACT expected code, with 124 reported as its own loud failure — a "non-zero means blocked"
  assertion would have accepted the hang and would not have caught this defect. The payload is piped,
  never fed to the hook with `<<<`, which would hang the test itself at exactly these sizes.

- README hook table: the six guards registered under the `Bash|PowerShell` matcher were all listed
  as `PreToolUse · Bash`; no row named PowerShell at all.

### Note on the version bump

Patch, deliberately. Payloads in the 65536-65663 band that previously slipped through on a cancelled
hook are now blocked, but nothing LEGITIMATE becomes refused that these guards did not already intend
to refuse — the fix restores the documented contract rather than widening it. (The 0.21.0 minor was
called out for an *acceptance* change that could refuse previously-allowed legitimate work; this is
not that.)

## [0.22.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.21.0]

### Fixed

- **`block-dangerous-git`'s hash-width probe ignored a wrapper's chdir, so an unsafe
  `--force-with-lease` passed.** A lease expectation is judged against the hash width of the
  repository the push will run in, and the probe replays git's own repository-locating globals to
  find it. It could not replay a WRAPPER's relocation: `collect_git_locating_opts` reads only the
  slice between the git word and the subcommand — as it must, since that walk cannot know which of
  `env`'s or `sudo`'s options take a value — so `env -C <sha256-repo> git push
  --force-with-lease=main:<40-hex>` probed the invoking SHA-1 directory, read the 40-hex expectation
  as an immutable object id, and allowed the push. Where git actually runs, that same word is an
  ordinary movable ref name, which is the exact hole `--force-with-lease` exists to close.
  `hook::git_resolve_index` already records the relocation in `HOOK_GIT_RESOLVED_WRAPPER_DIRS` — it
  is the only parser that can tell a real `env -C <dir>` from the `-C` in `env -u -C git`, which
  moves nothing — and the probe now replays it as leading `-C` words, ahead of git's own, so the two
  compose in execution order under git's rules rather than being modelled. Covered for `env -C`,
  `env --chdir=`, `sudo -D`, the composition with git's own `-C`, and the `env -u -C` non-chdir.
  **Acceptance behavior changes** (hence a minor bump): a wrapped push whose lease is a movable name
  where git runs is refused where it was allowed, and one whose lease is a real object id there is
  allowed where the misplaced probe refused it.

- **`skill-reference-verify` reported references an Edit never touched, missed short substring
  edits, and could spend its whole 30-second timeout on one large Edit.** Partial-Edit
  reconstruction located the hunk by line and then filtered the whole line by word token. All three
  defects were that filter: an untouched broken reference sharing a physical line with the hunk was
  readmitted by any word it happened to share (`legacy` in both the edited prose and
  `` `/alpha:ghost-legacy` ``); an Edit replacing fewer than four lowercase characters produced no
  token at all, so reconstruction gave up and every such edit went uncovered; and locating spent two
  full-file `grep` processes per hunk line, which a thousand-line Edit turned into a timeout — an
  advisory lost entirely, after delaying the tool call to get there. Reconstruction now reads the
  file once and keeps only the inline-code spans whose extent OVERLAPS the located anchor. Overlap
  is exact where the token filter was approximate, and has no minimum length to clear. The
  occurrence-uniqueness gate is unchanged: an anchor that cannot say which occurrence the edit
  landed on is still dropped rather than unioned.

  The timeout half needed both halves of its cost removed. Dropping the subprocesses left the
  per-line RESCAN, which is anchors TIMES file size — measured on a Windows/Git Bash host, a
  thousand span-free hunk lines still cost 82 s against the 30-second budget. The hunk is written to
  disk contiguously, so it is now located WHOLE: one scan for the entire edit, and the span set is
  the same one the per-line walk produced, since a line anchor's extent is the text the edit wrote
  on that line and the whole hunk's extent is the union of exactly those. The same measurement is
  now 11 s at a thousand lines and 11 s at four thousand — the hunk-size term is gone. Locating
  whole is also strictly better scoping: a hunk whose every line repeats but whose whole text does
  not used to be dropped as ambiguous line by line, and now resolves to the one place it names. The
  per-line walk survives as a fallback for a hunk that is no longer on disk verbatim — another
  PostToolUse hook reformatting the file between the write and this read is the realistic cause.

  Measuring the scan itself then contradicted the bound that had been placed on it. One scan is not
  linear in file size, it is QUADRATIC — 0.07 s at 32 KiB, 0.24 s at 64, 1.07 s at 128, 3.94 s at
  256 on the same host, because bash's `%%` pattern strip walks the string rather than indexing it.
  A 4 MiB file, which the previous cap allowed, is ~18 minutes for a SINGLE scan, so the guard's
  worst case had never actually been bounded, only moved. Reconstruction now stops above 128 KiB,
  and the fallback's anchor cap falls along that same curve instead of being a flat count — 58
  anchors at 32 KiB, 14 at 64, 3 at 128. Above the cap the direct hunk scan is unaffected, so a
  complete reference is still reported and only partial-edit recovery stops, which is this guard's
  permitted failure direction. Both numbers are calibrated end to end against the hook rather than
  from the isolated curve, which understates the cost: it times an anchor that matches near the end,
  where one strip walks the file and the second is free, while a no-match strip walks it twice and
  the whole-hunk probe pays a scan before the fallback runs at all. Covered by a case that puts a
  large file and the fallback path TOGETHER, which neither the timing case (whole-hunk fast path)
  nor the correctness cases (three lines) reached. That case asserts what the cap DOES rather than
  how long it takes — one reference inside the cap is still reported, one past it is not — because a
  wall-clock bound there measures the host: the same fixture read 21 s loaded and a smaller one 23 s,
  against an isolated scan of ~1 s at that size. A timing assertion that noisy fails on load and
  passes on a regression that happens to run on a quiet box.

- **`skill-reference-verify` reported a valid command as unresolved when its plugin declared custom
  skill paths.** Resolution hard-coded `plugins/<plugin>/skills/`, but a manifest's `skills` key
  holds a path or array of paths that ADD to that directory, and a declared path may point straight
  at a directory holding `SKILL.md` ([Plugins
  reference](https://code.claude.com/docs/en/plugins-reference), "Path behavior rules"). A skill
  loaded from a declared location now resolves, as does the documented single-skill layout (a root
  `SKILL.md` with no `skills/` subdirectory and no `skills` key). That layout is honoured under its
  stated conditions only — a root `SKILL.md` beside a populated `skills/` is not loaded by Claude
  Code, so accepting it would suppress the advisory for a command that does not exist.

  The advisory's own text was wrong the same way the resolution had been: it named
  `plugins/<plugin>/skills/` as the place searched, whatever the manifest declared. The message now
  lists the directories the search actually covered, built from the same `skill_roots` the
  resolution used. The advisory ends by telling the reader to confirm against the tree, and pointing
  them at the wrong part of it is the one instruction that cannot survive being wrong. A plugin
  using the conventional layout still reads exactly as before.

## [0.20.0]

### Changed

- **The two behavioral-class advisory injectors now default OFF: `flag-commit-pr-skill-bypass` and
  `workflow-resilience-check`.** Issue #2021's hook-surface classification found these are the
  plugin's only two clean behavioral-class context injectors — fixed prose that consults no external
  ground truth (`flag-commit-pr-skill-bypass` emits a static nudge toward `/pull-request create`;
  `workflow-resilience-check` runs two greps and emits a fixed ~120-word checklist asserting nothing
  the model cannot derive). Per `docs/PLUGIN-PHILOSOPHY.md` "Instruction economy", a hook that
  corrects model behavior is an ablation candidate, and the evidence-gated order is **config-disable
  first where a kill switch exists** — so the scripts and their wiring stay, and a consumer opts back
  in by setting the existing `flag_commit_pr_skill_bypass_enabled` / `workflow_resilience_check_enabled`
  userConfig option to `true`. Deletion, if ever, is a separate change gated on ablation evidence.

  **Mechanism, stated because the shared helper's fallback points the other way:**
  `hook::check_enabled` reads the `CLAUDE_PLUGIN_OPTION_<NAME>_ENABLED` process mirror with an
  UNSET-means-true fallback, which would silently re-enable a default-off hook anywhere the harness
  does not materialize userConfig defaults into the environment. Both hooks therefore switch to an
  explicit opt-in test (`[[ "${VAR:-false}" == "true" ]] || exit 0` — the same shape session-flow's
  default-off `observer-arm` uses), and the `plugin.json` defaults flip to `false` so the
  configuration dialog and `${user_config.*}` agree. Per the current plugins reference
  (<https://code.claude.com/docs/en/plugins-reference>, fetched 2026-08-08), `default` is the
  "Value used when the user provides nothing" and options are "exported to hook processes as
  `CLAUDE_PLUGIN_OPTION_<KEY>`"; the script-side default is what makes the OFF posture hold when
  that export is absent. Each test suite now exports the switch ON for its behavior cases and pins
  the unset-switch no-op as its own case.

- **`block-noncanonical-commit` narrowed to the actual hazard: only a `-m` message that REALLY
  contains a newline blocks.** The guard used to deny every `git commit` that was not the `-F -`
  stdin form — `git commit -m "fix: typo"` included — which #2021 classified hybrid: the multi-line
  `-m` cross-shell mangling is a policy-grade hazard, but the blanket width policed style. Now:

  - a single-line `-m` passes; a `-m`/`--message` value carrying an actual newline blocks, in every
    spelling the argv scan sees — separated (`-m <msg>`), attached (`-m"<msg>"`), `--message=<msg>`,
    every accepted unique abbreviation of `--message` (any prefix from `--m` up to one letter
    short of the full spelling, separated or `=`-attached — git's parse-options accepts any
    unique long-option prefix and `--message` is git commit's only `m`-initial long option;
    verified on git 2.55), and a short-option cluster ending in `m` (`-am <msg>`);
  - bare `git commit` / `git commit -a` (no message source; the old block) now pass — no `-m`, no
    mangling hazard;
  - repeated single-line `-m` flags pass: git itself joins them as paragraphs, no shell newline is
    involved;
  - the exemptions are unchanged (`--amend`, `-C`/`-c`, `--fixup`/`--squash`, `-F`, in-progress
    sequencer), as are the fail-closed structural refusals (`--config-env` alias shape,
    alias-traversal budget, unparsable PowerShell);
  - on the PowerShell tool a here-string `-m` value still blocks: the classifier blanks the body to
    a placeholder, so its content — multi-line by construction of the form — cannot be inspected,
    and the guard fails closed on it. A single-line literal PowerShell `-m` passes;
  - the `block_noncanonical_commit_allow` token `message-flag` now means "permit `-m` even with a
    newline"; the kill switch is unchanged.

  **Accepted residual, fail-OPEN and documented in the hook header:** a message attached to a
  short-option cluster (`-am"multi<NL>line"`) is not recognized — which cluster letters take values
  is per-option knowledge the scan does not model — consistent with the guard's friction-not-sandbox
  posture. The test suite is respelled in both directions: every alias/wrapper/traversal fixture
  that asserted a block now carries a real-newline `-m` payload (so it still pins the machinery it
  was written for), and new cases pin the allowed single-line forms.

- **`hooks.json`: the two structurally separate PreToolUse groups carrying the identical
  `Bash|PowerShell` matcher are merged into one six-hook group.** Pure wiring cleanup flagged by
  #2021 — behavior is identical: per the current hooks reference
  (<https://code.claude.com/docs/en/hooks>, fetched 2026-08-08), all matching hooks run in parallel,
  and same-matcher groups are separate entries that each fire independently, so one group of six and
  two groups of four-plus-two schedule the same work.

### Fixed

- **Three stale hook headers said "Triggered on Bash tool calls" while wired `Bash|PowerShell`:**
  `block-hook-bypass.sh`, `block-noncanonical-commit.sh`, and `flag-commit-pr-skill-bypass.sh` now
  say Bash and PowerShell (cosmetic; the wiring itself was already correct).

## [0.19.5]

### Fixed

- **`block-hook-bypass` missed the explicit stdout redirect entirely — `cat 1>file` and
  `echo x 1>file` were never caught.** `1>file` writes the file exactly as `>file` does, but both
  detection patterns only ever admitted the bare `>`: `_cat_redir` required `cat[[:space:]]*>` and
  `_echo_file_out` excluded any operator preceded by a digit, in order to keep `2>` out. That
  exclusion took the legitimate fd-1 spelling with it, so a single character defeated both lanes of
  the guard. Verified live against the shipped hook before the fix: `cat 1>real.txt` exited 0 while
  `cat > real.txt` exited 2.

  Both patterns now admit the explicit `1` before the operator. Other fds stay out: `_echo_file_out`
  still rejects a digit-prefixed operator except that `1`, so `2>` and `21>` do not match, and the
  `cat` lane matches neither. The fd-1 discard (`cat 1>/dev/null`) is still a discard, since the
  exemption reads the effective stdout target.

  **Three things a naive `1?>` widening gets wrong, all now pinned by cases.** (1) The fd digit
  needs a COMMAND BOUNDARY: `cat[[:space:]]*1?>` also matches `cat1>file`, an unrelated binary named
  `cat1` with an ordinary redirect, so the two spellings stay separate branches
  (`cat[[:space:]]*>` for the zero-space form, `cat[[:space:]]+1>` for the explicit one) — the same
  word-boundary discipline `_producer_head` already applies to echo/printf. (2) An fd DUPLICATION or
  close has no file operand: `cat 1>&2` and `cat 1>&-` are not writes, and the segment is skipped
  when no file target was found. (3) That skip needs the target class to reject BOTH spellings of
  the dup's `&` — the literal one a correct `normalize_segments` restore produces, and the `\x01`
  sentinel that survived when the restore silently failed (see the next entry). Excluding only one
  of the two lets a dup read as a file named `2`, or as one named `\x012`, depending on the bash in
  use. Verified across the full matrix: write forms block, discards and dups and other-fds pass.

  **This was pre-existing, not a 0.19.3 regression.** 0.19.3 widened the same `1?>` spelling on the
  EXEMPTION side (`set_last_stdout_target`, so `cat >/dev/null 1>real.txt` could not sneak a write
  past the discard check) and did not touch detection. The two sides disagreeing is what left the
  hole visible: the exemption understood a spelling the detection never looked for.

- **`echo x >&2` and `printf x >&2` were blocked as file writes on bash 5.2 and newer.** Writing to
  a duplicated fd is not a file write, and both were refused. Reproduced against the shipped hook:
  `echo x >&2` exited 2 on `main`, 0 after the fix, while `echo x >&2 > real.txt` still exits 2 —
  bash applies redirections left to right, so the file is the effective stdout target there.

  **Cause: a substitution replacement that stopped meaning what it said.** `normalize_segments`
  protects a redirect `&` with a `\x01` sentinel so an fd dup is not split as a control operator,
  then restores it with `${normalized//"$soh"/&}`. Since **bash 5.2**, an unquoted `&` in a
  substitution REPLACEMENT expands to the text the pattern just matched — the `sed` rule — so that
  line restored the sentinel to itself. A silent no-op on new bash, still correct on old: the guard
  quietly behaved differently depending on the interpreter running it. The surviving `\x01` then
  matched `_echo_file_out`'s target class, and the producer lane — unlike the `cat` lane — has no
  emptiness skip, so an empty effective target fell through to a block. Restoring with `\&` fixes
  it. Confirmed by dumping the stored segment: `cat 1>&2` normalized to `$'cat 1>\0012'` before,
  `cat 1>&2` after.

  **Two defenses are kept against the same class of regression.** The sentinel exclusions in
  `_redir_scan` stay, so a dup is rejected whichever byte reaches the scan; and
  `producer_redirect_bypass` gained the `cat` lane's emptiness skip, whose absence is what turned an
  empty effective target into a block in the first place. Both are unreachable while the two target
  classes agree — which is precisely the equivalence that failed silently here.

## [0.19.4]

### Fixed

- **`block-dangerous-git`'s movable-lease block no longer prescribes a form it rejects.** The
  message told producers to pin the expectation with
  `--force-with-lease=<refname>:$(git rev-parse <ref>)`, but detection is static over the literal
  command string and never evaluates substitutions, so `$(git rev-parse <ref>)` reached the scan as
  an unresolved name in the `<expect>` slot and was blocked by the very message prescribing it. With
  every stated-expectation spelling rejected, amend-and-force was effectively unavailable without
  widening `block_dangerous_git_allow`; two independent producer lanes hit this and fell back to
  corrective commits.

  The message now prescribes what the hook already accepts — a literal object id of the repository's
  full hash width, resolved by running `git rev-parse` as a **separate** step — and says why a
  substitution cannot stand in for it. The no-expected-value message gained the same clause, so a
  producer bounced there does not walk into the movable block next.

  **Acceptance behavior is unchanged** (hence a patch bump): the literal-SHA form was already
  accepted, and the plain `--force`, bare `--force-with-lease`, refname-only, movable-name, and
  `${VAR}` / `$(…)`-in-`<expect>` forms are all still blocked. New cases assert the message text
  itself, the surface that was wrong.

## [0.19.3]

### Fixed

- **`block-hook-bypass` no longer blocks a READ-ONLY inline `open()`.** The python write-indicator
  set matched a bare `open[[:space:]]*\(`, so `python3 -c "import json; d=json.load(open('x.json'))"`
  — a read — was refused as a Write/Edit bypass. Reproduced verbatim against the shipped hook.

  **Design call (the discrimination boundary, stated because `open(f,'w')` and `open(f)` differ only
  by an argument):** `open(` on its own now says nothing about direction and is no longer an
  indicator. It counts as a write only when a python WRITE-MODE LITERAL also occurs in the same
  command — a quoted token built solely from mode characters, containing at least one of
  `w`/`a`/`x`/`+`, in an argument position (immediately after a comma, or after `mode=`). Read modes
  (`'r'`, `'rb'`, `'rt'`) carry none of those characters and no longer trip it.

  The check is **co-occurrence, not position**, and deliberately so: Bash ERE has no lazy quantifier,
  so a positional `open\([^)]*'w'` stops at the first `)` and would fail OPEN on a genuine
  `open(os.path.join(a,b),'w')`, while a greedy `.*` reaches into unrelated text anyway. This is the
  same mangle-resistant co-occurrence shape the PowerShell lane already uses, and it is checked in
  both directions by new cases.

  **Accepted residual, in the fail-CLOSED direction:** a read-only `open()` in a command that
  separately contains an argument-position `'w'`/`'a'`/`'x'`/`'+'` literal — e.g.
  `print(open('f').read(), 'a')` — still blocks. The argument-position requirement is what keeps the
  common read shapes clear: a dict subscript (`json.load(open('p'))['a']`) is preceded by `[`, not by
  a comma. **Second accepted residual, unchanged from before:** a bare `pathlib` mention is still an
  indicator on its own, so read-only inline python that merely imports `pathlib` still blocks. That
  indicator carries the `.write_text(` / `.write_bytes(` block today; narrowing it needs an explicit
  write-call set and is a separate change.

  **Test fixtures respelled, not relaxed.** Four PowerShell-lane cases asserted the accepted
  mention-over-block (and the here-string inertness) using a bare `open(` as their stand-in write
  indicator. Since a bare `open(` no longer *is* one, those inputs are respelled to `open(f,'w')` so
  they keep testing the contract they were written for; a new case asserts that the same mention
  carrying only a READ-mode open is now allowed, which is the fix rather than a hole.

- **`block-hook-bypass` no longer blocks `cat > /dev/null`.** A discard is not a file write, so the
  exemption the echo/printf lane already granted now applies to the `cat >` lane too, including the
  quoted spellings (`cat > "/dev/null"`, `cat > /dev/"null"`). The exemption is **segment-scoped**,
  not command-scoped: `cat > /dev/null && cat > real.txt` still blocks on its second segment. The
  `cat` scan and the echo/printf scan now share one segment splitter (`normalize_segments`) instead
  of two, so they cannot drift on escaped separators or on the `2>&1` fd-duplication sentinel.

  **The exemption resolves the segment's EFFECTIVE stdout destination, never the mere presence of a
  `/dev/null` redirect** — and getting that wrong would have been a one-token bypass of this entire
  guard. Bash applies redirections left to right, so `cat > /dev/null > real.txt` writes to
  `real.txt`, as does `cat >/dev/null 1>real.txt`. A presence test would have exempted both: write
  the discard first, the real file second. `set_last_stdout_target` walks the segment's stdout
  redirects and keeps the LAST target; only `/dev/null` there exempts. The inverse order
  (`cat > real.txt > /dev/null`) is a genuine discard and stays allowed.

  This replaces `_echo_devnull`, which was the same order-blind presence test on the echo/printf
  lane — that half was **pre-existing**, not introduced here, and both lanes now share the helper.
  The scan admits the explicit stdout spelling `1>` (`1>file` is stdout exactly as `>file` is) while
  excluding other fds (`2>`, `21>`), the combined form (`&>`), and fd duplications (`>&1`, whose
  target class excludes `&`). It sets a global rather than echoing: it runs per segment on every
  Bash call, and a command substitution would add a fork to each one.

- **`flag-commit-pr-skill-bypass` is registered at `timeout: 60`, not `10` (was the only guardrails
  hook below its siblings).** Measured runtimes of 12–19 s against a 10 s cap meant the hook was
  cancelled on essentially every firing: the commit/PR-skill advisory never ran, while still costing
  its full cap on every Bash/PowerShell call. Per the current hooks reference
  (<https://code.claude.com/docs/en/hooks>, fetched 2026-08-08), `timeout` is *"Seconds before
  canceling. Defaults: 600 for `command`, `http`, and `mcp_tool`; 30 for `prompt`; 60 for `agent`.
  `UserPromptSubmit` lowers the `command`, `http`, and `mcp_tool` default to 30, and `MessageDisplay`
  lowers it to 10."* — nothing in the harness pushes a `PreToolUse` `command` hook toward 10, so the
  value was authored. 60 is this file's established value for the same matcher (the other five
  `Bash|PowerShell` guards all carry it); the documented default is 600. The same page states that
  *"Hook entries merge across settings levels rather than replacing each other: user, project, and
  local settings add their own hooks without removing managed ones"*, so a consumer had no way to
  raise a plugin's timeout locally — which is why this had to be fixed in the plugin.

- **`cli-flag-verify` no longer reports npm's global config flags as hallucinated.**
  `npm ci --prefix ./vendor` was flagged `UNKNOWN_FLAG`. `--prefix` is one of npm's config keys, and
  every config key is simultaneously a command-line flag on every subcommand — `npm --help` says so
  itself ("Specify configs in the ini-formatted file … or on the command line via:
  `npm <command> --key=value`"). Those keys appear in neither `npm <subcmd> --help` nor `npm --help`,
  and the authoritative list (`npm config ls -l`) prints `prefix = "…"`, not `--prefix`, so a generic
  `--help` flag-list parser cannot consume it. `npm` therefore joins `git` and `npx` as an excluded
  binary in `DEFAULT_BINS`, on the same recorded rationale: a non-exhaustive `--help` produces only
  real-flag false positives. Consumers who want it back can re-add it through the
  `cli_flag_verify_bins` option. **A per-subcommand→top-level `--help` fallback was considered and
  rejected as the fix**: it was measured against this repro and `npm --help` does not list `--prefix`
  either, so it would not have closed the finding.

### Changed

- **`block-dangerous-git` and `block-no-verify` read their payload with `hook::jq_fields`.** Both
  extracted `.tool_input.command` and `.tool_name` with two separate `jq` invocations; they now take
  both from one, using the helper `0.19.2` added to the shared lib. On Windows Git Bash a process
  spawn is `fork()` emulation (~140 ms), and both guards run on every Bash/PowerShell tool call.
  Failure semantics are unchanged: a missing `jq` or an unparsable payload exits 0 exactly as the
  empty-command skip did, after `hook::require_jq` has already surfaced the degraded state once per
  session.

## [0.19.2]

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

## [0.19.1]

### Fixed

- **The PowerShell git sink no longer blocks a call-operator / dot-source of a CONSTANT target
  (#1968).** `ps::might_invoke_git`'s call-target branch matched any quote character after `&` or
  `.`, so `& "C:\tools\publish.ps1"` — the ordinary PowerShell script-invocation idiom, carrying no
  `git` token and a compile-time-constant path — routed to the fail-closed sink and was refused by
  a *git* guard. Both quote styles and the dot-source form were affected, and because the predicate
  is shared, the identical command false-blocked twice: once from `block-dangerous-git` and once
  from `block-no-verify`. The branch now matches only a genuinely computed target — a bare variable
  or subexpression (`& $tool`, `& (…)`), or a double-quoted string that INTERPOLATES
  (`& "$tool"`, `& "C:\tools\$ver\x.exe"`). Per PowerShell
  [`about_Quoting_Rules`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_quoting_rules),
  a `$`-free double-quoted string and any single-quoted string are compile-time constants, so such
  a target is statically decidable as non-git. No fail-open: the literal-git probe runs
  quote-INTACT, so `& 'git' …`, `& "git" …`, and `& "C:\Git\cmd\git.exe" …` are still caught by
  name; the interpolated forms still block. Regression cases for both directions are checked in on
  both guards' suites.

- **The sink's block message named constructs that were not present, and omitted the one that
  was.** Both unparsable-command messages listed backtick / `--%` / subexpression / script-block /
  here-string regardless of which of the four sink triggers actually fired, so an operator blocked
  by a launcher or a computed call target was told to "remove the unparsable construct" when there
  was none to remove. `ps::classify_git_command` now records the trigger in `PS_SINK_TRIGGER` and
  each message prints a remediation line specific to it.

- **The unbalanced-here-string message names the terminator that matches the opener.** PowerShell
  pairs `@'` with `'@` and `@"` with `"@`
  ([`about_Quoting_Rules`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_quoting_rules)),
  but the remediation line always said `'@`. An operator whose `@"` body was flagged and who
  followed the advice literally produced a command that was still unbalanced and still blocked.
  `ps::blank_herestrings` now records the hanging opener's quote in `PS_HERESTRING_QUOTE` and the
  line names the matching terminator, falling back to naming both when no opener was recorded.

- **The dynamic-invocation message no longer prescribes the form the operator already used.** It
  told them to "invoke the target by its literal name" and asserted that a constant quoted path is
  not blocked — but the invocation FORM is what routes a command to this branch, so
  `& 'git' reset --hard` names its program literally and is blocked anyway. Following the advice
  changed nothing. The detection is unchanged and correct: `&` plus a quoted string is what the
  guard's Bash tokenizer cannot read, so the command is refused unless it is provably git-free.
  The line now says to drop the `iex` / `&` / `.` and write the program as a plain command word,
  which is actionable for every shape that reaches it.

- **The sink remediation lines are now asserted on their TEXT, not just their exit code.** Both
  message defects above survived because every PowerShell sink case checked only that the command
  was blocked; `block-no-verify.test.sh` now captures stderr and pins the terminator selection and
  the drop-the-operator advice.

- **The fail-closed sink message now names its kill switch.** Unlike the sibling too-long and
  alias-cap fail-closed messages, the unparsable-command messages omitted the
  `block_dangerous_git_enabled` / `block_no_verify_enabled` escape hatch, leaving an over-blocked
  operator with no documented way out.

### Changed

- **Telemetry distinguishes the four sink triggers.** Both guards emitted a single
  `powershell-unparsable` form token for all four shapes that reach the fail-closed sink, which
  hid which one was responsible for a false-positive rate. The token now carries the trigger:
  `powershell-unparsable-herestring-unbalanced`, `-special-construct`, `-dynamic-invocation`,
  `-launcher`.

- **The git and python-write lanes answer "is this call target computed?" with one shared
  predicate.** The two lanes had drifted to different regexes for the same question — the git
  lane's blanket quote match is what produced the false positive above, while the python lane's
  interpolation-only match was already correct. The separator class and operator shape now live in
  one place (`ps::call_target_is_bare_computed`, `ps::call_target_is_interpolating_string`); each
  lane states at its call site which of the two shapes it admits. The python lane's behavior is
  unchanged — it takes the interpolating-string half only, as before. The shared operator prefix is
  spelled out in each predicate rather than concatenated in from a variable: mixing an unquoted
  variable with adjacent literal regex text in a `[[ =~ ]]` pattern is version-sensitive, and a
  predicate that quietly stops matching fails OPEN. The two named functions are the seam that
  prevents drift; a string constant would not have added to that.

## [0.19.0]

### Changed

- **`block-noncanonical-commit` now DEFERS a PowerShell command the classifier cannot parse
  instead of blocking it (#1858).** `ps::classify_git_command` rc 2 means "not faithfully
  tokenizable, and something git-shaped is in there" — a form this guard never got to read, so its
  block message named a commit shape it never saw while `block-dangerous-git` blocked the same
  input with a message describing what was actually observed. The rc-2 arm now takes the same
  `exit 0` the sibling content gate `block-convention-violation` already takes, collapsing both
  nonzero arms into one deferral. Both arms emit a new telemetry `form` value,
  `powershell-deferred`, so a deferral stays distinguishable from an evaluated allow (rc 1
  previously exited with no telemetry record at all).

  **Residual exposure, stated rather than buried.** The two guards that retain the rc-2 block —
  `block-dangerous-git` and `block-no-verify` — each carry their own kill switch, so a
  configuration setting `block_dangerous_git_enabled` and `block_no_verify_enabled` to false while
  leaving `block_noncanonical_commit_enabled` on no longer blocks a git-shaped unparsable
  PowerShell commit. Under a default install, and under any configuration retaining either
  sibling, coverage is unchanged. The contract test asserts both halves — the deferral here, and a
  live block on the same two inputs from each sibling, matched on the block reason — plus the
  residual itself with both kill switches off, so the deferral cannot silently become a hole.

### Fixed

- **Five telemetry schemas no longer claim their guard is Bash-only.**
  `hooks.json` registers `block-noncanonical-commit`, `block-no-verify`, `block-dangerous-git`,
  `block-hook-bypass`, and `flag-commit-pr-skill-bypass` on `Bash|PowerShell`, and each emits the
  payload's real `tool_name`, but every one of their schemas under
  `docs/conventions/hook-telemetry/data/` described `tool` as always `"Bash"` and `subject` as
  always the tokenized `Bash:<first-token>` form. A PowerShell call is not tokenized —
  `hook::extract_bash_subject` returns the bare tool name — so both claims were wrong for half the
  matcher. Descriptions corrected; no payload change.

## [0.18.5]

### Fixed

- **Shared-heavy content could push hardcoded-path-check past its hook timeout, and a guard killed at
  its timeout fails open.** The macOS block defanged `Shared` tokens inside a per-candidate `while
  read` loop, spawning a `sed` and a `grep` for every candidate line. The loop's only escape was the
  trailing `head -3`, which fires when candidates *survive* the defang — so on a block where every
  candidate is a legitimate `Users/Shared` reference, nothing was ever written, the short-circuit
  never closed the pipe, and the loop ran to completion. The guard was slowest on precisely the
  innocent content the exclusion exists to serve, and fastest on violations.

  The defang now runs once over the whole candidate block. `sed` is line-oriented in this pipeline —
  no `N`/`H` multiline commands, and `$` anchors per line in both shapes — so hoisting cannot change
  any individual line's result. A `grep -nE` over the defanged block yields the block-relative
  indices of the survivors, and `awk` selects those lines from the **original** block by `NR`, so the
  reported entry still carries the original line number and original un-defanged text. `grep -E`
  remains the sole matcher; `awk` does no regex work, so no second regex dialect enters and the
  shared `HPP_*` bodies stay the single source of truth.

  A block containing no `Shared` token at all skips the pipeline entirely via a bash-builtin
  substring test — the defang is a provable no-op there, so the common case costs nothing.

  The subprocess count is now constant instead of proportional to the candidate count. Measured
  through the hook over the same corpora on one machine, swapping only this library: the
  per-candidate loop spawned 210 `grep`/`sed` processes at 100 Shared-only lines (100 `sed` + 110
  `grep`) and its wall clock grew 13x for a 4x input increase — 22s at 100 lines to 288s at 400. The
  hoisted form spawns 12 at either size and holds flat at ~10s. The regression case pins that count
  rather than a wall-clock ratio: elapsed time here is dominated by process-spawn latency, and
  repeats of the identical 400-line corpus measured 5.0s and 15.2s — a spread wider than the signal
  a timing ratio would have to resolve.

- **The survivor re-test now strips `grep -n`'s line-number prefix before matching.** The hoisted
  form re-tests the defanged candidates, and those lines still carried the `<n>:` prefix the first
  `grep -n` added — so a violation at **column 0** reached the re-test as `<n>:/Users/…` and could no
  longer satisfy the left boundary's `^` alternative. It matched only because the boundary class also
  accepts `:`, which is there for yaml/docker value position and carries no obligation to this
  pipeline: narrowing that class for its own stated purpose would have silently dropped a violation
  the first pass had already flagged. The strip is one more expression on the `sed` the defang
  already runs, so it costs no extra process, and it keeps both passes matching identical bytes
  rather than coupling the second to an unrelated member of the class. Pinned by a column-0 case.

- **The macOS candidate pipeline could abort a scan under `set -e`.** The candidate block now ends in
  an explicit `|| true`: its trailing `grep -v` exits non-zero whenever nothing survives the Windows
  exclusion — the common clean case — and this library is sourced by commit-time hooks whose shell
  options it does not control. Aborting there would fail open, the same failure mode the hoisting
  addresses.

## [0.18.4]

### Fixed

- **`block-hook-bypass`'s block message now states the scope the guard actually has (#1802).** The
  message said a write was prevented and that Write/Edit is the sanctioned path, with nothing about
  scope, so it read as "shell file writes are blocked". The guard is deliberately producer-scoped
  over a single command string, and the gap runs in both directions: an agent concludes shell file
  writes are unavailable and contorts around a restriction a script file does not have, while a
  human credits the guard with coverage it never claimed — the more expensive error where the guard
  is load-bearing in someone's threat model.

  Verified against the hook with fixture input: `printf 'x' > out.log` blocks, while `bash
  execute.sh` — whose script may write freely — is allowed, as reported. Two shapes the report did
  **not** name are allowed too, and they matter for the wording: `bash execute.sh >> run.log` and
  `sort data.txt > out.txt` are *direct redirects in the command string* and are allowed by the
  producer-scoped design, as is `cat a.txt b.txt > c.txt` (only the stdin-consuming `cat > f` form
  is a write workaround). So the report's suggested line — "direct redirects in this command only" —
  would have overstated coverage in the other direction. The shipped note says instead that only
  this command string is inspected — known shell file-write forms plus recognized inline
  interpreter code (`python -c` IS scanned, so the blind spot claims only an invoked script file
  or a program's own opaque code) — and that a redirect produced by another program is not seen.

  No hook logic changes. The behaviour the note describes is now pinned by tests beside the
  message-content assertions, so the two move together.

- **The `README` residuals section names the same scope**, next to the existing quoted-span residual
  for this guard, so the guarantee is stated where consumers read the guard's limits rather than
  only at the moment of a block.

## [0.18.3]

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

## [0.18.2]

### Fixed

- **A wrapper's options were parsed as git's globals, bypassing the commit guard.** The directory and
  locating-global helpers — `effective_dir`, `collect_locating_globals`, `explicit_git_dir` — were
  handed the whole pre-git argv slice, wrapper arguments included, and they cannot know which wrapper
  options take a value. In `env -u -C git …`, GNU env's `-u NAME` consumes `-C` as the variable to
  unset and `git` as the command, so git itself receives no `-C` and never changes directory; the
  0-based slice instead read the bare tokens `-C git` and resolved into `./git`. The guard then
  inspected one repository's aliases while git executed another's — a reported, reproducible bypass
  in which `env -u -C git -c alias.a='!git -C child p' a` returned 0 while real git committed via
  `child`'s `commit --allow-empty -m`.

  Those helpers now receive only the slice from the **resolved git token** to the subcommand. The two
  sites that rebuild the command line still start at index 0, deliberately, because they reconstruct
  the invocation rather than parse git's options.

  The regression cases were verified to **fail against the unfixed hook** and pass against the fix,
  and git's own `-C` is covered alongside them so the narrower slice cannot silently stop honouring a
  relocation git really performs.

- **A wrapper's chdir moved git but no longer moved the guard.** Excluding wrapper argv from
  git-global parsing must not discard a relocation the wrapper genuinely performs. GNU env documents
  `-C, --chdir=DIR` as "change working directory to DIR", so `env -C other git a` runs git in `other`
  and resolves `other`'s alias — while a slice beginning at the git token cannot see that operand at
  all and read the payload cwd's alias instead. `hook::git_resolve_index`, the only parser that can
  tell env's `-C` from `-u`'s operand, now reports the wrapper's chdir in
  `HOOK_GIT_RESOLVED_WRAPPER_DIRS`, and the guard composes it ahead of git's own globals.

  Five spellings are read — `-C DIR`, `-CDIR`, `--chdir DIR`, `--chdir=DIR`, and a clustered
  `-vC DIR` — because one unhandled spelling is the whole bypass again; a repeat within one `env` is
  last-wins against the invoking cwd, as env itself resolves it. `sudo`'s own `-D`/`--chdir` is read
  in its unclustered spellings. A `NAME=value` operand now ends option parsing as env's own grammar
  does, so `env FOO=1 -C dir git …` — which env refuses to run at all — no longer records a chdir
  that never happens.

  A sixth spelling is deliberately NOT covered: a chdir smuggled through `-S`/`--split-string`
  (`env -S '-C dir git …'`). That path already fails open on `main` for any command, because the
  resolver's post-splice restart re-enters outside env's option parsing — a distinct control-flow
  defect in shared code, tracked in #1814 rather than folded into this fix.

  The resolver half of this lands in the shared `lib/hook-utils.sh` and is synced to every carrying
  plugin; guardrails is the only plugin that consumes the new global.

## [0.18.1]

### Fixed

- **Shared `hook-utils.sh`: an in-project file spelled as a Windows 8.3 short name is no longer
  silently skipped (#1636).** `hook::physical_path` canonicalized with GNU realpath, which under
  Git Bash resolves symlinks but leaves 8.3 short names (`KYLESE~1`) unexpanded, so a short-form
  `file_path` — the shape Claude Code's own scratchpad paths take — failed the
  `CLAUDE_PROJECT_DIR` prefix comparison in `hook::read_file_path` and the advisory hooks that
  consume it (`stale-path-verify`, `skill-reference-verify`, `cli-flag-verify`) skipped the file
  silently: no verification, no notice, no telemetry. The lib now expands short names on
  Windows/MSYS hosts (new `hook::expand_8dot3`, via `cygpath -l`) before the comparison, and
  only when the expanded form actually differs — a legitimate long name containing `~` passes
  through untouched, and a genuinely out-of-project file is still skipped: that
  defense-in-depth scoping is deliberate and preserved. 8.3 generation is a per-volume property
  (`fsutil 8dot3name query`), so the defect was live only for checkouts on a volume that
  generates short names — and invisible to contributors whose checkouts sit on one that does
  not. Synced from `lib/hook-utils.sh`.

## [0.18.0]

### Fixed

- **A large but legitimate `Write` is no longer BLOCKED by the stdin read bound (#1563).**
  `hook::buffer_stdin` read the hook payload with `read -d ''`, which consumes a pipe one byte at a
  time (~32 KB/s on Git Bash), so the `stdin_read_timeout` bound was really a **~64 KB throughput
  ceiling** rather than the stall detector it was written to be. Past that ceiling the read returned
  a truncated payload and returned rc 2, and all seven blocking guards here — `hardcoded-path-check`,
  `secret-pattern-detection`, `block-no-verify`, `block-dangerous-git`, `block-hook-bypass`,
  `block-noncanonical-commit`, `block-convention-violation` — mapped that to `exit 2`, blocking a
  write whose content was never even scanned. Observed in the field as a full-file write of an
  844-line document being blocked repeatedly, forcing the author to write it in five chunks;
  reproduced here end-to-end with a benign 100 KB payload.
  The read is now chunked (`read -N`), which bash satisfies with block reads, and the bound became a
  true **idle** bound: `read -t` is a deadline for the whole requested read rather than an inactivity
  timer, so a timed-out read that nevertheless returned bytes is now treated as progress — its
  partial chunk is kept and the read continues. Only the absence of bytes for a whole
  `stdin_read_timeout` is a stall, and that still fails closed with rc 2 exactly as before. The bound
  is read in four slices, because `read -t` reports only that its window expired and never when
  inside it the last byte arrived — armed as one window, a stall would be declared anywhere between
  one and *two* bounds after the pipe went quiet. Slicing caps that overshoot at a quarter-bound;
  that residual quarter is the limit of the approximation and always errs toward waiting. Slicing
  needs fractional `read -t`, so on a shell without it (Bash 3.2, the macOS system shell) the bound
  is read as one window and the one-to-two-bound overshoot remains — documented as such rather than
  claimed away. Reading on
  stops once the buffer already parses as whole JSON, so the Win32 late-EOF case (payload complete,
  pipe simply never closed) settles at the payload rather than at the bound. Measured: 50 KB drops
  from ~2100 ms to ~20 ms, 200 KB from ~6800 ms to ~85 ms.
  `read -N` is Bash 4.1+, and these hooks support Bash 3.2+ (macOS system bash), so the pre-4.1 path
  falls back to the delimiter read inside the same re-arming loop — same guard and rationale as
  `context-guard`'s `statusline-tee.sh`.
  **The fail-closed posture is unchanged** — a stalled pipe still yields rc 2 (regression test in
  `lib/hook-utils.test.sh`), a payload containing a violation is still blocked, and a violation
  sitting at the very end of a 200 KB payload is now *caught* rather than swept up in a
  content-blind block. Synced from `lib/hook-utils.sh`.

### Added

- **`stdin_read_timeout` userConfig option.** This plugin's hooks already read
  `CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT` through the shared library but never declared the option,
  so consumers had no supported way to set it — `actionlint` and `claude-ops` both declare it.
  Declaring it exposes the same knob here. The effective default when a consumer sets nothing remains
  the shell-level `:-2` fallback inside `hook-utils.sh`. A configured value the running shell's
  `read -t` will not accept — including a fractional value on a Bash release that has no fractional
  timeouts — falls back to that default instead of failing every read, and `0` is rejected outright
  because it would make `read` return without consuming anything. Acceptance is settled by probing
  the running shell rather than a Bash version table.

## [0.17.3]

### Changed

- **Test scaffolding: migrated `mktemp -p` temp file/dir creation to the portable `mktemp "$DIR/template"` form.** BSD/macOS `mktemp` has no `-p` flag; the directory now rides in the positional TEMPLATE argument instead, which both GNU and BSD `mktemp` accept identically. Test-only — no hook behavior change. Part of #1527 (`block-dangerous-git.test.sh`, `block-hook-bypass.test.sh`, `block-no-verify.test.sh`, `cli-flag-verify.test.sh`, `flag-commit-pr-skill-bypass.test.sh`, `guardrails-test-helpers.sh`, `hardcoded-path-check.test.sh`, `secret-pattern-detection.test.sh`, `skill-reference-verify.test.sh`, `stale-path-verify.test.sh`, `workflow-resilience-check.test.sh`).

## [0.17.2]

### Fixed

- **`stale-path-verify`: partial-`Edit` reconstruction adjudicated citations on
  lines the edit never touched**, violating the diff-scope contract the hook
  states it holds. The anchor match is `grep -F`, a substring match, so when the
  whole `new_string` is a bare fragment the line anchor collapses onto the token
  anchor it was introduced to replace: an `Edit` whose hunk is `docs` recovered
  every line containing `docs` and reported a pre-existing stale citation among
  them.

  Reconstruction says it mirrors `skill-reference-verify`, and that sibling
  already carries the gate this guard omitted: an anchor is used only when it
  **occurs exactly once** in the file. Occurrences, not matching lines — two
  occurrences on one physical line are a single `grep` hit, and a line-uniqueness
  gate would adjudicate a citation sharing that line. Occurrences are counted by
  walking start offsets with awk's `index()`, not with `grep -o`, because
  `grep -o` emits only non-overlapping matches: an anchor of `docs/docs` against
  `docs/docs/docs` starts at two offsets whose spans overlap, so `grep -o`
  reports one and a self-overlapping anchor would pass the uniqueness gate it
  should fail — recreating the very advisory the gate was added to prevent. The
  anchor reaches awk through the environment rather than `-v`, since `-v`
  processes escape sequences in the value and would silently transform an anchor
  containing a backslash. Per the
  [tools reference](https://code.claude.com/docs/en/tools-reference) an `Edit`'s
  `old_string` "must appear exactly once", so a unique anchor pins the edit to
  the line carrying it; a non-unique anchor cannot say which occurrence the edit
  landed on and is dropped rather than guessed at. `replace_all: true` is read as
  the one shape where repetition is the edit's own footprint rather than an
  ambiguity, so uniqueness is not required there.

  Partially addresses
  [#1455](https://github.com/melodic-software/claude-code-plugins/issues/1455) —
  its Face B (over-recovery at or above the four-character token floor). Face A,
  the floor itself swallowing a sub-four-character replacement such as `js` →
  `md`, is untouched and remains open.

  **This narrows what the guard reports.** Dropping an ambiguous anchor can cost
  a true positive when an edit lands in text that repeats verbatim elsewhere in
  the file, so 0.17.0's measured firing envelope (0.20% of tracked markdown at
  50% precision) no longer describes the guard exactly. For a detect-then-judge
  advisory that is the right side of the trade — it is degraded far worse by
  being wrong when it speaks than by staying quiet.
- **`stale-path-verify`: an unstaged deletion was silently exempted.** The
  sparse-checkout exemption tested `git ls-files --error-unmatch`, which reports
  an index entry for an ordinary unstaged deletion exactly as it does for a
  skip-worktree entry — it cannot tell the two apart. A genuine uncommitted
  removal, which is the working-tree disappearance this guard exists to
  adjudicate, was therefore skipped. The test is now the skip-worktree bit
  itself: `ls-files -v` tags a sparse entry `S` — lowercase `s` when the
  assume-unchanged bit is also set, since `-v` marks assume-unchanged by
  lowercasing the letter — an unstaged deletion `H`, and an assume-unchanged
  entry `h`. Only the skip-worktree letter, in either case, is exempted —
  assume-unchanged promises a path is unmodified on disk, not absent from it, so
  a deleted one is the same genuine disappearance as any other unstaged deletion.

Both were raised in review on
[#1432](https://github.com/melodic-software/claude-code-plugins/pull/1432) and
merged before they were resolved. Four behavioral cases pin them, verified red
against the 0.17.1 guard (`PASS=79 FAIL=4`) and green after; a fifth pins the
combined skip-worktree + assume-unchanged tag, and a sixth pins the
self-overlapping anchor described above — red against the `grep -o` counter
(`PASS=86 FAIL=1`), green against the `index()` one. The suite reports
`PASS=87 FAIL=0` at this snapshot.

## [0.17.1]

### Fixed

- **Git-alias CHAINS no longer bypass the git guards (`block-dangerous-git`,
  `block-noncanonical-commit`).** Both guards re-expand an inline/persisted git
  alias to re-check the real subcommand, but two coupled defects in that
  re-expansion let a dangerous op or a non-canonical commit reached through a
  SECOND alias hop slip past (verified rc=0 → fail open):
  - **The nested re-parse dropped the command-line globals.** The splice fed the
    recursive check words `0..gi` (wrappers + `git`) plus the expansion, dropping
    everything between `git` and the subcommand — i.e. the `-c` / `--config` /
    `--config-env` options. So the nested hop saw empty config: no second-hop
    alias definition and no `--config-env` shape to refuse. The splice now spans
    `0..sub_idx`, carrying every command-line global into each hop, so the
    already-value-blind `--config-env` shape refusal and the plain/`.command`
    max-danger union fire at every depth (closes the `--config-env`-second-hop
    manifestation and its `.command`-spelled variant by construction).
  - **Re-expansion was capped at one level** on the false premise that git does
    not chain aliases (it does — an expansion whose first word is itself an alias
    is expanded again). The one-level cap is replaced by a save/restore seen-set
    of resolved subcommand names: recursion follows the chain to the real op, and
    a repeat is git's own alias-loop stop (nothing runs — allow-safe), with
    termination guaranteed by the finite set of distinct alias keys. Covers plain
    inline chains, `--config-env` hops, the `alias.<sub>.command` spelling, and
    the commit guard's persisted-config alias chain.
  - **A `!` shell-alias body no longer inherits the outer chain's alias-loop
    state** (review finding on the fix above). git's alias-loop guard is
    in-process only: a `!` alias spawns a NEW git process whose loop guard
    starts empty, so a body that re-invokes a name from the outer chain
    (`git -c alias.a='!git -c alias.a="reset --hard" a' a`) is re-expanded
    there, not stopped. Every `!` reparse now runs under an emptied seen-set
    (restored afterwards). Termination: inline definitions reachable from a
    reparse are strict substrings of the parent segment's text, and the commit
    guard's persisted-config `!` hops — whose bodies never shrink — are bounded
    by a second save/restore seen-set of persisted name/expansion pairs, where
    a repeat models real git's endless fork of a self-referential persisted
    shell alias (`a = !git a`): nothing ever runs, so skipping is allow-safe.
  - **Chain traversal is now proportional to the chain's LENGTH, not exponential
    in it** (review finding on the fix above). Because each hop re-checks BOTH
    alias spellings independently, following the chain to the real op branched 2x
    per hop: a *benign* 10-hop, 402-character command cost 5.4s in
    `block-dangerous-git`, and an 8-hop, 356-character one cost 14.6s in
    `block-noncanonical-commit` (every leaf forked a `git config`) — and a hook
    that stalls stops guarding. Two bounds, both guard-local:
    - **Equivalent analysis states collapse.** A verdict is a pure function of
      (alias seen-set, argv); every other input is invocation-constant, and a
      block is a process-wide `exit 2`, so a state reached a second time while
      the process still runs provably did not block and cannot decide otherwise
      now. Skipping the repeat is exact, not a coverage trade — and it is what
      collapses the common shape, where both spellings of a hop expand to the
      same thing, to one path per hop. Persisted-alias lookups are cached per
      (directory, subcommand) for the same reason, removing the per-leaf fork.
    - **A total re-expansion budget, fail-CLOSED.** Collapsing cannot bound a
      chain whose two spellings DIFFER, because each path carries its own
      trailing text forward and no two states are equal. The ceiling counts
      ANALYSES, not seconds — a wall clock is host- and command-length-dependent
      — and is calibrated against the linear walk the guards already accept: a
      memoized traversal spends one analysis per hop, so a branching walk is
      capped at the same order as a long non-branching chain (in
      `block-dangerous-git`, at strictly less than the ~430-hop chain its 16 KB
      command ceiling admits). It sits far above real usage; every legitimate
      command measured spends single digits. Exhausting it blocks: the guard
      could not finish deciding, so it must not allow.
  - **A persisted `!` alias chain that DESCENDS through nested repositories is no
    longer mistaken for a self-cycle** (`block-noncanonical-commit`; review
    finding on the fix above). One alias text can mean a different hop in every
    repository it appears in: with `alias.a = !git -C child a` in a repository
    *and* in its child, plus `alias.a = commit --allow-empty -m bypass` in the
    grandchild, real git descends twice and creates the non-canonical commit —
    but the cycle key was the name and expansion only, so the second hop read as
    a repeat, the walk stopped, and the guard returned 0 (verified fail-open).
    The effective repository is now part of that key, and it is COMPOSED across
    each `!` reparse rather than restarting from the payload cwd, because a `!`
    body runs as a new git invocation from the repository the outer one resolved
    — so a relative `-C` inside it stacks. Termination is unchanged where it came
    from the set: a body with no `-C` leaves the directory alone, so
    `a = !git a` and mutually referential pairs still stop on the first repeat.
    A body naming the directory it is already in (`-C .`) would otherwise mint a
    fresh key per hop and walk instead of stopping (measured 34.6s); it now
    collapses to a repeat (0.8s) via the identity described in the next bullet,
    which is also what supplies the `!` body's base — so a body invoked from a
    SUBDIRECTORY composes from the outer repository's top level, as git does.
    `block-dangerous-git` is not affected — it resolves inline aliases only, with
    no persisted lookup and no shell-alias seen-set.
  - **The guard no longer MODELS git's path semantics; it asks git**
    (`block-noncanonical-commit`; two review findings on the fix above, one root
    cause). Modelling resolution in shell text produced a bypass every time it was
    attempted, in both directions:
    - **Lexical `x/..` cancellation is wrong when `x` is a symlink.** With
      `base/link -> target/child`, `git -C link/.. …` enters `target` on a POSIX
      host, but textual cancellation reduced the lookup to `base` — so a
      `commit -m` alias in `target` went unseen.
    - **Resolving physically instead would be just as wrong, with the opposite
      bias.** Verified on git 2.54.0.windows.1: `cd -P link/..` reports the link
      target's parent while `git -C link/..` reports "not a git repository",
      because Win32 normalizes `..` textually. A shell resolver would send the
      guard to a repository git never enters.
    - **A `!` body starts at the outer repository's TOP LEVEL**, not where the
      outer command ran. Invoked from `<repo>/sub` with `alias.a = !git -C child
      a`, git reaches `<repo>/child`; carrying the subdirectory forward made the
      guard probe `<repo>/sub/child` and miss a nested repository's `commit -m`.

    The lexical normalizer is deleted rather than patched. Composed `-C` paths are
    now handed to git verbatim, and one primitive —
    `git -C <dir> rev-parse --show-toplevel --show-prefix` — supplies both the `!`
    body's launch directory and the canonical repository identity in the
    shell-alias cycle key, so the guard tracks git's behavior on every platform by
    construction. Where git chdirs the body (a nonempty prefix, or pure discovery)
    identity canonicalizes for free: `-C .`, `link/..`, a subdirectory, and every
    other spelling of one repository collapse to a single key, which is what stops
    a self-rewriting `-C` chain. Resolution failure **falls back to the literal
    composed directory** (best-available, not a gate), scoped to the alias walk
    only, so an ordinary `git commit -F -` resolves nothing and forks nothing
    (measured: 0 git subprocesses; the `-C .` chain stops after 4, not the 128
    traversal budget; a 20-hop inline chain still forks 0).

  - **A `!` shell-alias body under explicit locating globals launches where the
    CALLER stands, not at the work-tree top level** (`block-noncanonical-commit`;
    review finding on the fix above). git chdirs a `!` body to the top level only
    when it can compute a prefix — when the caller's directory sits INSIDE the
    effective work tree, which repository discovery always satisfies. An explicit
    `--git-dir`/`--work-tree` whose work tree does not contain the caller skips
    that chdir: verified on git 2.54.0.windows.1 (reported by review on 2.43.0),
    from `<out>`, `git --git-dir <g> --work-tree <w> -c alias.a='!git -C child p'
    a` runs `<out>/child`'s persisted `p`, while the same invocation from
    `<w>/sub` runs from `<w>`. Collapsing to the top level UNCONDITIONALLY probed
    the benign `<w>/child` and allowed while real git ran `<out>/child`'s
    `commit -m` (verified fail-open) — and its mirror false-blocked a canonical
    commit. The launch directory is now read from git's own answer: nonempty
    `--show-prefix` (or a probe with no locating globals, i.e. pure discovery)
    returns the top level, an empty prefix under explicit globals returns the
    caller's composed directory. The inside-the-work-tree branch is unchanged, so
    a subdirectory caller still resolves from the top level, as git does.

  - **The launch-directory probe is boundary- and newline-safe** (two review
    findings on the fix above). Both were fail-open holes in the launch-directory
    lookup itself:
    - **The launch-directory CACHE key encoded each argv word `%q`, not `$*`.**
      Joining the replayed locating globals with `$*` flattened argv boundaries,
      so `--git-dir 'X --work-tree' --namespace Z` and `--git-dir X --work-tree
      '--namespace Z'` — which git interprets as different repositories — produced
      one key. In a payload with two git segments, the first poisoned the shared
      cache for the second, handing it the first segment's directory while git
      launched the second elsewhere and ran the caller's non-canonical alias.
      Keying each word `%q`-encoded makes the key injective on the argv, so no two
      distinct argvs collide.
    - **The toplevel and prefix are read in SEPARATE `rev-parse` calls.** One
      combined `--show-toplevel --show-prefix` call split on the first newline; a
      repository path containing an INTERIOR newline truncated the toplevel and
      misread the remainder as a prefix, switching the walk to the wrong directory.
      Two calls put each field in its own capture, so an interior newline can no
      longer be read as the boundary into the next field. The prefix call is
      skipped when the toplevel is empty, so the common allow path pays no extra
      fork.
    - **Each field is captured byte-exact through a sentinel** (a third review
      finding, on the two-call fix above). `$(…)` strips EVERY trailing newline,
      but a top-level path may itself END in one (POSIX permits any byte but NUL
      and `/`), so the strip returned a different sibling directory — the same
      fail-open, now at the tail rather than the interior. A sentinel byte printed
      after git's output absorbs the strip; git's terminator is then removed
      explicitly. git ends these two `rev-parse` forms with a BARE LF, not a CRLF,
      even on Windows (verified on git 2.54.0.windows.1 via `od -c`), so exactly
      one trailing `\n` is peeled and nothing else — a `tr -d '\r'`/`%$'\r'` peel
      would corrupt a path that legitimately ends in `\r`, the identical hole one
      byte over. Interior and trailing newlines (and a trailing `\r`) now survive
      in both fields. The framing is unit-verified against every newline position
      (interior, single- and double-trailing, CRLF terminator); an end-to-end
      fixture is impractical because reaching a newline top level requires either a
      literal newline in the parsed command or a newline-ending payload `cwd`, and
      the latter is stripped one layer earlier — a SEPARATE, pre-existing entry
      point shared with `main`, tracked as
      [#1536](https://github.com/melodic-software/claude-code-plugins/issues/1536)
      rather than absorbed here.

    The invocation's LOCATING globals are replayed onto that probe, not just its
    `-C`. `--git-dir` and `--work-tree` locate a repository as surely as `-C` does
    (git's own usage lists both as globals before `<command>`), and asking without
    them answered "no work tree" for a perfectly locatable one — so
    `git --git-dir=<r>/.git --work-tree=<r> -c alias.a='!git commit -F -' a` run
    outside a tree had a **valid canonical commit refused**. The replay keeps the
    ask-git property intact: `git --git-dir=X --work-tree=Y rev-parse
    --show-toplevel` is still git's answer, not a reconstruction of one. Its `-m`
    twin is pinned too, so the replay did not simply switch the fail-closed branch
    off.

    `.` and `..` both need special handling only if the guard resolves paths
    itself, and it no longer does. Every `.` spelling (`.`, `./././.`) resolves to
    one identity, so a self-rewriting chain stops on the cycle key without a
    `.`-cancelling pass. `..` is left to git as well rather than refused outright:
    refusing every `..` path would be cheap and fork-free, but it false-blocks a
    legitimate `git -C sub/.. commit -F -`, which is now a regression case
    alongside its `commit -m` twin — asking git separates the two, blanket refusal
    cannot.

    Words after the subcommand are no longer read as repository globals. They are
    that subcommand's own arguments — or, for an alias, text git APPENDS to the
    expansion — so a trailing `-C` is not a global:
    `git -c alias.a='!git b #' a -C <other-repo>` resolved to `<other-repo>` and
    missed a `commit -m` reached in the CURRENT one, because git starts the body at
    the current repository's top level and the `#` discards the appended words.
    Directory resolution now sees only the invocation prefix, which also stops
    `git commit -C HEAD` (`--reuse-message`) reading as a directory named `HEAD`.

    **Standing limitation, unchanged and still open:** the guard does not evaluate
    shell relocation, so a `!` body that moves the process (`!cd child && git …`)
    is analyzed against the invoking repository rather than the destination. Real
    git resolves the destination's aliases, so an alias defined only there is not
    seen. Modelling this means evaluating arbitrary shell word expansion, which
    this guard deliberately does not do; asking git cannot help either, because
    git is never told about the `cd`. Tracked in
    [#1486](https://github.com/melodic-software/claude-code-plugins/issues/1486),
    with a reverted working attempt and the four findings that landed against it as
    a map of what a real fix must handle.

    Identity is a **best-available answer, not a gate**: when git cannot resolve a
    work tree the walk continues with the literal composed directory, which is the
    behavior this guard already had. An interim revision failed CLOSED there and was
    dropped, because it never earned its place — its own justification was that a
    commit could not have succeeded there anyway (so it protected against nothing),
    while it produced three separate false positives, each refusing a VALID
    canonical commit reached through a repository the OUTER probe could not see:
    `--git-dir`/`--work-tree` on the invocation, then `-C` inside the body. The class
    it was added for is open either way — the persisted-alias lookup still drops the
    locating globals, here and on `main` alike
    ([#1501](https://github.com/melodic-software/claude-code-plugins/issues/1501)).
    Deferring resolution to the nested invocation is the real fix and is tracked as
    its own design question
    ([#1500](https://github.com/melodic-software/claude-code-plugins/issues/1500))
    rather than bolted on at this depth.

  Guard-local change only (no `hook-utils.sh` change, no cross-plugin sync).
  Test matrices extended in both guards with two- and three-hop chains, the
  `--config-env` and `.command` second-hop variants, a persisted-config alias
  chain (fixture repo), the shell-alias outer-chain re-invocation (blocked) with
  its canonical/undefined twins (allowed), a persisted chain crossing a `!` hop
  (blocked / `-F -` allowed), 20-hop dual-spelling chains under a hard wall-clock
  ceiling (safe terminal allowed, dangerous terminal still blocked — the collapse
  costs no coverage), a 60-hop single-spelling chain (allowed: the budget bounds
  branching, not depth), a divergent-spelling chain (blocked on the budget), a
  three-level nested-repository fixture whose grandchild `commit -m` must block
  (with its canonical twin allowed), a `-C .` self-reference that must collapse to
  a cycle (with a twin proving a real `commit -m` behind a `-C .` hop still
  blocks), a `!` body invoked from a SUBDIRECTORY that must resolve from the outer
  repository's top level (canonical twin allowed), a `!` body under explicit
  `--git-dir`/`--work-tree` whose caller sits OUTSIDE the work tree that must
  launch in the caller's own child repository (bypass + false-block twins), with
  the inside-work-tree pair proving the top-level branch is unchanged, a
  symlinked-parent `-C link/..`
  fixture gated on the platform actually resolving through the symlink (asserted on
  POSIX, skipped loudly on Windows, where git is itself textual), `-C ./././.`
  collapsing to a cycle without a `.`-cancelling pass, `-C sub/..` reaching a
  `commit -m` (blocked) beside its canonical twin (allowed, which is why `..` is
  not refused outright), and benign controls (safe multi-hop chain allowed; alias cycle, self-
  and mutually referential persisted shell aliases terminate and allow without
  hanging). Closes #964.

## [0.17.0]

### Added

- `stale-path-verify` — a twelfth guard, advisory on `PostToolUse` `Write|Edit`
  of markdown. It flags a repo-relative path cited in an inline code span that
  this repository's own history shows was **deleted** and that is gone from the
  working tree.

  This ships the rescope of the `asserted-path-verify` guard withdrawn at
  0.16.0 (see that release's *Not shipped*), resolving
  [#1314](https://github.com/melodic-software/claude-code-plugins/issues/1314).
  The withdrawn guard tested **absence** behind a first-segment gate, inferring
  that a path was a claim about this tree because its leading directory existed
  here. That inference is invalid: `docs/`, `scripts/`, `lib/` and `.claude/`
  are conventional names shared by every repo that uses them, so the gate
  selected for path *shape* rather than repo *ownership*. Swept across all 975
  tracked markdown files it fired on 23.7% of them at **zero** precision.

  The gate is now **provenance**: the exact repo-relative path must appear in
  `git log HEAD --no-renames --diff-filter=D --name-only`. Absence proves
  nothing on its own — it becomes evidence only against a baseline of presence,
  and history is the only thing that can establish one.
  - `--no-renames` is mandatory. Under git's default rename detection a moved
    file is recorded as `R` and `--name-only` prints only the *new* path, so the
    stale path never enters the set and the guard silently drops to zero
    findings. A behavioral test case pins it.
  - `HEAD`, not `--all`: a path that only ever existed on an abandoned branch is
    not a stale mainline citation.
  - The history walk is built lazily, only after a cited path has already failed
    the working-tree existence test, so the overwhelmingly common quiet path
    never pays for it.
  - A shallow clone truncates that history, which would leave the guard inert
    while appearing healthy, so it emits a visible prerequisite notice naming
    `git fetch --unshallow` instead.
  - The walk's exit status is checked before anything is populated. A clone that
    is not shallow can still fail mid-walk — a partial clone offline, a damaged
    object store — emitting the deletions it already resolved and then exiting
    nonzero. Read through a pipe that status is invisible, and a truncated set
    is indistinguishable from a complete one: the guard would adjudicate against
    a fraction of history while looking healthy. A failed walk takes the same
    announced degradation as a shallow clone, and a behavioral test case pins it
    against a fixture whose walk emits one deletion and then fails
    (review-caught).
- An `Edit` that replaces a bare substring **inside** an existing code span is
  reconstructed from disk, mirroring `skill-reference-verify`. The surrounding
  backticks are pre-existing and never enter `new_string`, so the hunk holds no
  complete span to scan and a newly-stale citation would otherwise be missed
  entirely. Only the lines the hunk's own text occurs in are read back, and only
  candidates containing one of the hunk's 4+ character word tokens are
  adjudicated. Both filters are needed to hold diff-scope: a word token alone is
  short enough to occur in lines the edit never touched — a bare `docs` in
  unrelated prose matches every citation under `docs/` — so an untouched stale
  citation elsewhere in the file would fire. Every line of `new_string` is on
  disk verbatim by `PostToolUse` time, so anchoring on the line can only ever
  select a subset of what the token would, and the edited line is always in it.
- The existence gate reads **present**, not reachable. `-e` alone reports false
  for two paths that are deliberately there: a dangling symlink, where the link
  exists and only its target does not, and a path tracked at `HEAD` but left
  unmaterialized by a sparse checkout. Both would otherwise clear the provenance
  gate and be reported stale, so the gate also accepts `-L` and, for a candidate
  that has already satisfied provenance, consults index membership.
- Markdown **link destinations are out of scope**; only inline code spans are
  scanned. On-disk link integrity belongs to the repo's offline link checker,
  and under the provenance oracle no link-kind candidate contributed a finding.
  Dropping them removes the document-directory base, `../` canonicalization,
  percent-decoding and lexical normalization — a large share of the withdrawn
  guard's complexity, none of it earning signal.
- `CHANGELOG.md` writes are excluded, mirroring `skill-reference-verify`: an
  append-only historical record documents exactly the removed paths this oracle
  selects for.
- A finding names the surviving file when exactly one tracked path now carries
  the cited basename. Basename matching is far too weak to trigger on — `README.md`
  and `SKILL.md` match hundreds of paths — but once history has established the
  path was removed, a unique match is very likely where it went.

### Changed

- The guard is declared **detect-then-judge**, not deterministic. Its oracle is
  mechanical, but the conclusion is not: a doc may cite a removed path
  deliberately, as a deletion or completion record, and that citation is correct
  exactly as written.
- This is a **charter change, not a tightening**. The withdrawn guard claimed to
  catch hallucinated paths; a provenance gate structurally cannot. An invented
  path was never in the repository, so it never enters the deleted-path set and
  the guard stays silent by construction. Separating "asserted about *this* tree"
  from "documented about a *consumer's* tree" needs a signal a repo-root oracle
  does not have — both are absent locally and conventionally shaped — so that
  class is deliberately deferred until one exists.
- README guard counts and the per-hook kill-switch table are re-measured against
  the wired hook set rather than carried forward: the prose said "eleven safety
  guards" and "four advisory guards", and the kill-switch table omitted
  `block-convention-violation` and `skill-reference-verify` while both were
  wired and toggleable.
- The guard is registered as a hook-telemetry producer:
  `docs/conventions/hook-telemetry/data/stale-path-verify.schema.json` publishes
  its `data` payload and the convention's implementer table carries the row.
  Under the convention's discovery contract a sink treats a hook with no
  matching schema as unknown and ignores its `data`, so an unpublished producer
  emits telemetry nothing can consume (review-caught).
- The two degradation branches emit telemetry `status: skipped` rather than
  `ok`. They run precisely when the deleted-path oracle was unavailable, so
  reporting `ok` made a sink read an un-run check as a healthy one — the same
  looks-healthy-while-inert failure the visible prerequisite notice exists to
  prevent, reintroduced on the observability surface. A behavioral case pins the
  shallow-clone branch's status (review-caught).

## [0.16.3]

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

## [0.16.2]

### Fixed

- **`skill-reference-verify`'s partial-Edit reconstruction now anchors on the hunk's own text, and
  only where that text occurs exactly once, instead of on its word tokens (#1453).** The guard's
  header comment claimed the token filter held the diff-scope contract — a pre-existing unrelated
  reference sharing a recovered line never fires — but a 4+ character word token is short enough to
  occur where the edit never landed: a hunk of unrelated prose containing `legacy` grepped back every
  `*-legacy` reference in the file, including an untouched broken one, which then passed the
  substring gate and fired from an edit that never touched it. Anchors are now the hunk's own lines,
  each on disk verbatim by `PostToolUse` time, and an anchor is used only when it **occurs exactly
  once**; anything repeated cannot say which copy the edit landed on and is dropped rather than
  unioned. Occurrences, not matching lines — two copies on one physical line are a single `grep` hit,
  so inserting `legacy` into a line that already carried an untouched `` `/alpha:ghost-legacy` ``
  would otherwise still fire. The token filter survives as a second gate on what the locator returns,
  never as the locator. `replace_all` is read from the payload and exempted: there every occurrence
  is a site this call edited, so requiring uniqueness would silence the guard on a genuine multi-site
  break. Costs, stated rather than papered over — an edit landing in text that repeats verbatim
  elsewhere goes unreported, and under `replace_all` a line that independently read the same is kept
  even though the edit never touched it. Both are the right side of the trade for a detect-then-judge
  guard, degraded far worse by speaking wrongly than by staying quiet, and reconstruction stays a
  best effort rather than a proof. Four regression tests cover the shared-token, bare-token,
  same-line-double-occurrence, and `replace_all` shapes; the existing partial-replacement
  true-positive cases keep passing, with the composite (complete-reference-plus-bare-word) case
  reshaped onto a realistic multi-line hunk since a single Edit's `new_string` cannot land in two
  disjoint places on disk. `stale-path-verify` and `cli-flag-verify` carry the same reconstruction
  shape and are not fixed here; the guard-wide false-positive class they belong to is tracked on
  `#547`, and `#1432` (`65b4f67c`) is the sibling fix this ports from.

## [0.16.1]

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

## [0.16.0]

### Added

- `block-dangerous-git` distinguishes the `--force-with-lease` forms instead of
  treating them all as safe, under a new `push-lease-unsafe` form token. A lease
  passes only when its expectation is one git cannot re-resolve to something
  newer while the push runs; everything else is blocked, in the two kinds
  [git-push(1)](https://git-scm.com/docs/git-push) itself treats differently.
  - **No expected value** — bare `--force-with-lease` and
    `--force-with-lease=<refname>` lease against the remote-tracking ref, which
    git warns "interacts very badly with anything that implicitly runs
    `git fetch`" and is "trivially defeated if some background process is
    updating refs in the background". Blocked unless `--force-if-includes`
    (git 2.30+) is present, which git documents as the mitigation for exactly
    these forms.
  - **A movable `--force-with-lease=<refname>:<expect>`** — `origin/main`,
    `HEAD`, a tag, an *abbreviated* object id (per
    [gitrevisions](https://git-scm.com/docs/gitrevisions), git resolves a short
    hex word as a ref before trying it as an object-id prefix, so a tag named
    `dead` beats the object whose id starts `dead`), or hex of the wrong width
    for the repository's hash format. Blocked unconditionally: git declares
    `--force-if-includes` a "no-op" alongside an explicit `:<expect>`, so
    nothing mitigates this form.

  What passes: `<expect>` an object id of **the pushed repository's own hash
  width** (40 hex under SHA-1, 64 under SHA-256, read once from
  `git rev-parse --show-object-format`; undeterminable fails closed), or the
  empty string, which asserts the ref must not exist. The other width is not
  accepted: git ignores a ref whose name is full-width hex for its own format,
  but a 64-hex name in a SHA-1 repository — or a 40-hex one under SHA-256 — is
  an ordinary ref git resolves at push time, so it moves like any other name.
  git's repository-locating globals (`-C`, `--git-dir`, `--work-tree`,
  `--namespace`) are replayed onto that probe, so `git -C <sha256-repo> push`
  from a SHA-1 directory is judged by the target. git scopes
  a pin to its own ref, so a bare fallback alongside a pinned entry still governs
  every other ref being updated. Where one ref carries several lease entries git
  consults the first and ignores the rest, and the guard follows that same
  first-match rule rather than latching on any later spelling. A trailing
  `--no-force-with-lease` cancels every previous lease. Unique-prefix
  abbreviations (`--force-w`, `--force-i`) are handled; a push dry-run still
  disarms the check, and after `--` the words are operands rather than flags.

## [0.15.1]

### Fixed

- **PreToolUse blocking guards were declared with `timeout: 10`/`15` — 40-60x below the platform's
  own documented `command`-hook default of 600s for `PreToolUse` (only `UserPromptSubmit` (30) and
  `MessageDisplay` (10) lower it; `PreToolUse` does not — <https://code.claude.com/docs/en/hooks>,
  fetched 2026-07-25) — causing the harness to kill them before completion under real machine load
  and let the guarded tool call proceed with no `permissionDecision` from that guard.** Measured at
  86.1% of PreToolUse runs killed at the declared timeout across 3,923 runs on one machine
  (melodic-software/claude-code-plugins#1345). Confirmed against this session's own local
  `~/.claude/projects/*/*.jsonl` transcript: a `hook_cancelled` attachment for
  `block-convention-violation.sh` (`timedOut: true`, `durationMs: 10184` against `timeoutMs: 10000`)
  was immediately followed by the guarded Bash tool call executing and returning a real result — the
  guard's verdict was silently lost, not merely slow. Standalone timing of all seven affected guards
  in this repo (no concurrent hook load) completed in well under 1.5s each, and the source contains no
  network calls or unbounded loops — confirming the guards are not inherently slow; the declared
  timeout was simply provisioned far below what the platform allows and below what real (contended)
  runs need. `timeout` raised from 10/15 to **60** (10-40x more headroom over the every real duration
  sample this investigation captured, while staying well short of the 600s platform default so a
  genuinely hung process is still bounded) for the seven **blocking** PreToolUse guards:
  `secret-pattern-detection`, `hardcoded-path-check`, `block-no-verify`, `block-dangerous-git`,
  `block-hook-bypass`, `block-noncanonical-commit`, `block-convention-violation`. The two **advisory**
  PreToolUse hooks (`flag-commit-pr-skill-bypass`, `workflow-resilience-check`, which never block
  regardless of outcome) and the PostToolUse hooks are unchanged — a missed advisory notice is not the
  fail-open security defect this fix addresses. This mitigation narrows the timeout-driven fail-open
  window; it does not remove it — a harness-killed hook process cannot itself report a decision, and
  what should happen to the guarded tool call when a *blocking* guard is killed (deny by default vs.
  today's silent fallback) is a harness-level policy question outside a plugin's control, tracked
  separately.

## [0.15.0]

### Added

- `skill-reference-verify` (advisory, PostToolUse Write|Edit): flags a
  `/plugin:skill` reference in markdown that does not resolve. Gated twice — it
  does nothing outside a marketplace repo, and within one it only adjudicates a
  plugin that repo's own manifests own. Resolution goes through manifest `name`
  and skill frontmatter `name`; a renamed skill's DIRECTORY name is deliberately
  not an alias, since treating it as one would suppress exactly the stale
  pre-rename references this guard exists to catch. The reference is the leading
  command token of a code span, so argument-bearing invocations
  (`/plugin:skill --apply`) are scanned. `CHANGELOG.md` is excluded as an
  append-only historical record: a rename entry must keep naming the old command.
  Declared **detect-then-judge**, not deterministic — globbing a plugins tree is
  exact only where the reference is locally owned, so the finding is a prompt for
  a human verdict and never an auto-fix.
- A README enforceability-tier section stating each guard's oracle class, so the
  detect-then-judge guard cannot be read as deterministic.

### Fixed

- README guard counts were stale before this change: the prose said "nine safety
  guards" and the table omitted `block-convention-violation` while ten were
  wired. Counts are now measured against the manifest's toggle set, and the
  missing row is present.

### Not shipped

- An `asserted-path-verify` guard was built alongside this one and withdrawn on
  measurement. Swept across all 975 tracked markdown files it fired on 23.7% of
  them — roughly one in four writes — producing 389 findings with **zero** true
  positives. 72% were consumer-project config paths (`.claude/**` and similar)
  that a doc describes for a CONSUMING repo and that correctly do not exist in a
  marketplace; its first-segment gate passed only because this repo happens to
  carry same-named top-level directories. Fixing the three dominant causes still
  left ~4% firing at zero true positives, so a repo-root filesystem test is the
  wrong oracle for a repo whose docs are largely about other repos' trees. The
  measurement is attached to its follow-up issue for rescoping rather than
  discarded.

## [0.14.3]

### Documentation

- `hooks/guardrails-test-helpers.sh` now points at
  `docs/conventions/shell-test-helpers/README.md`, the repo's owner doc recording that per-plugin
  shell assert-helper duplication and per-script exit-code taxonomies are deliberate, not drift. No
  behavior change.

## [0.14.2]

### Fixed

- **`block-hook-bypass` no longer lets an interpreter-producer write bypass the gate under the PowerShell
  tool (live-reproduced bypass).** The PowerShell branch classified only PowerShell cmdlet/redirect write
  forms (`ps::write_bypass`) and then `exit 0`ed **before** the shell-agnostic scans, so
  `python3 -c "open('x','w')…"` — the identical command the Bash lane blocks — executed unguarded when
  issued through the PowerShell tool. Reproduced end-to-end: same command, Bash → blocked, PowerShell →
  file written. The interpreter rule now also runs on the PowerShell lane. The **Bash** lane keeps its
  precise `python3 -c` scan (its `strip_literals` is genuinely quote-aware and Bash has no `<# #>` block
  comments or `&{}` script blocks) and additionally recognizes a **path-qualified** interpreter
  (`/usr/bin/python3 -c`, `.exe`), anchored on the `python3` basename so `notpython3` stays inert.
- **The PowerShell lane deliberately DIVERGES from the Bash lane and uses a fail-closed sink instead of a
  precise scan.** PowerShell is not faithfully bash-tokenizable, and a precise regex/normalize stack could
  not keep up — successive review rounds each surfaced a fresh evasion (path-qualified target, `&{python3}`
  script block, quoted-`#` comment truncation, with `<# #>` block comments and `-ArgumentList`
  arg-splitting still open). Following the repo's SINK DOCTRINE (`ps::classify_git_command` /
  `ps::might_invoke_git`), the lane now blocks on the mangle-resistant **co-occurrence** of (a) a raw write
  indicator (`_py_write`) and (b) a python3 interpreter token **plus** a `-c` inline-code flag, both seen
  on the quote-intact, backtick-recovered command (`ps::might_write_via_python3`). This uniformly closes
  the quoted / path-qualified / brace-glued / backtick-obfuscated / block-comment / arg-split forms. `-c`
  is **required** (position-independent), so a legitimate script or module run (`python3 build.py`,
  `python3 -m tool …`) that merely touches an `open(`-like path is **not** blocked; a **computed** flag
  (`python3 ('-'+'c') …`, `-ArgumentList ('-'+'c'),…`) is caught by fail-closing on a non-tokenizable arg
  subexpression (`ps::has_special_constructs`) when no literal `-c` is present, and a computed launcher
  TARGET that hides the interpreter name (`Start-Process -FilePath ('py'+'thon3') …`, `saps $exe …`) fails
  closed: any launcher present together with an unquoted computed construct (`$`/`(`) blocks, regardless of
  how the target is bound or how many options precede it (`-FilePath ('py'+'thon3')`, `-FilePath:$p`,
  `-NoNewWindow -FilePath $exe`) — while a literal non-python launcher (`Start-Process notepad …`) carries
  no such construct and stays allowed. A `-c` concatenated with an adjacent variable/subexpression
  (`python3 -c$code`, `python3 -c(…)`), which PowerShell joins into one `-c<source>` argument, is treated
  as a computed inline-code flag and fails closed (a longer literal flag like `-config` is not `-c`). A call
  operator / dot-source of a DOUBLE-quoted interpolated target (`& "$env:PYTHON_BIN" …`, `& "$(…)" …`) runs a
  computed interpreter and fails closed; a SINGLE-quoted target does not interpolate (`& '$x'` is a literal
  name) and stays allowed. **Accepted behavior
  change (fail-closed):** a command that only *mentions* `python3 … -c` + a write indicator in prose, a
  line/block comment, or a quoted string now **over-blocks** (three prior allow-fixtures flipped to
  expect-block); here-string mentions stay inert (blanked first, like the git lane). **Accepted residual:**
  a stdin heredoc (`python3 - <<PY … PY`, no `-c`) is uncovered, as it is today. Regression fixtures cover
  real `open(`/`pathlib` writes, every evasion form (path-qualified, script block, block comment,
  arg-split — MUST block), the flipped mention cases (MUST block), and script/module runs + read-only
  `os.path.normpath` + non-python quoted exe + here-string mention (MUST stay quiet). This was the
  in-comment "deferred to A2b" gap.

## [0.14.1]

### Fixed

- **`block-hook-bypass` `python-write` no longer false-positives on read-only `os.path.*path(` helpers
  (#1178).** The `_py_write` write indicator's `path[[:space:]]*\(` was an unanchored substring: it
  matched `path(` as the suffix of a longer identifier, so a pure path-arithmetic command
  (`python3 -c "…os.path.normpath(os.path.join(a,b))…"`) — and every other `os.path.*path(` helper
  (`abspath`, `realpath`, `relpath`, `commonpath`) — was blocked as a file-write bypass despite writing
  nothing. The `pathlib` / `path(` indicators are now identifier-boundary anchored so they still catch
  the write-capable `pathlib.Path(` producer while clearing the read-only helpers. Real writes stay
  blocked (`.write_text(`/`open('f','w')` match independently). Regression fixtures for each `*path(`
  helper (MUST-stay-quiet) plus a `pathlib.Path().write_text` (MUST-block) added to
  `block-hook-bypass.test.sh`.

## [0.14.0]

### Changed

- **Vendored convention resolver probes the well-known default neutral path (#163434).** The synced
  copy of `lib/resolve-convention-pattern.sh` now resolves the neutral convention SSOT by a fixed
  3-rung precedence: an explicit `## convention_source` pointer, else the well-known default path
  `docs/conventions/source-control/commit-convention.yml` when present, else the team markdown-H2.
  The CC-layer content gate enforces the same pattern the drafting side drafts against, with no
  pointer required in the common case. Back-compat: absent both a pointer and the well-known file,
  enforcement resolves from the markdown-H2 exactly as before.

## [0.13.0]

### Added

- **Vendored convention resolver understands the neutral convention SSOT (#1141).** The synced copy
  of `lib/resolve-convention-pattern.sh` now honors a team-tracked `## convention_source` pointer to
  a repo-relative flat-scalar YAML file: machine keys resolve from that file when it declares them
  (markdown-H2 fallback per key), the `Conventional Commits` keyword and the `pr_title_pattern`
  deferral marker work identically on both surfaces, a non-`posix-ere` `dialect:` declaration
  disables enforcement with a diagnostic, and a declared-but-broken pointer (absolute/backslash/`..`
  path, missing file) fails closed to no-enforcement rather than silently re-reading markdown values
  a migration may have retired. Policy floor unchanged: the pointer is honored from the team file
  only. Seam contract: `docs/conventions/commit-convention/README.md`.

## [0.12.3]

### Fixed

- **`hardcoded-path-check` skips when the project dir is not a git working
  tree (#1094, residual of #1038).** Claude Code sets `CLAUDE_PROJECT_DIR` for
  any directory — a home-directory session being the common case — and there
  the scope guard passed while every per-file exemption rung was unreachable:
  the `.claude` carve-outs don't cover machine-local plugin config
  (`~/.claude/<plugin>.conf`), and `git check-ignore` errors outside a work
  tree, leaving only the global kill switch. The scope guard now also skips
  when `git rev-parse --is-inside-work-tree` does not report a working tree
  (same rationale as the #1039 no-project skip: hardcoded paths only harm
  portable repo artifacts, and a non-worktree project dir has none). Bare
  repos skip too. README scoping bullet updated; tests pin the skip, the
  unchanged real-work-tree behavior, and the carve-outs now exercised inside
  real work trees.

## [0.12.2]

### Fixed

- **Machine-path bodies: right boundary is now the segment class, not a
  mandatory trailing separator (#1093).** The old bodies required a separator
  AFTER the child segment, which inverted detection both ways: a real bare
  path value at end of line (`root = <drive>:/Dev/GitHub`) was MISSED, while
  prose satisfied the requirement anyway — the space-permitting segment class
  greedily consumed words until a later slash on the same line, flagging a
  comment as "Windows repo path detected" while the actual violations passed
  clean. All five bodies in `machine-path-patterns.sh` now exclude whitespace
  and the double quote from the child-segment class and drop the trailing
  separator: bare values at a natural boundary (EOL, whitespace, quote) are
  detected, prose spans cannot match, and a bare ROOT with no child segment
  (`C:/Dev`, `/home`) still never matches. The driver's `/Users/Shared`
  exclusion covers the new bare form. 15 regression cases added (bare values
  in all five shapes, greedy-prose and root-plus-whitespace negatives, bare
  `Shared`). Synced-component note: the same pattern change lands upstream in
  `melodic-software/standards` `components/path-detection/` — the local and
  upstream copies must stay byte-identical or the next standards sync reverts
  this fix.

## [0.12.1]

### Fixed

- **`flag-commit-pr-skill-bypass` honors local-only plugin enablement (audit f2
  residual, follow-up to 0.9.9's user-global fix).** `source_control_enabled()`
  counted a `settings.local.json` value only when the project `settings.json`
  already declared the same key, so a plugin enabled ONLY at local scope
  (`claude plugin install --scope local` — a first-class state per the official
  plugins reference) resolved as disabled and the `gh pr create` advisory never
  fired. A local value now participates in per-key resolution unconditionally
  (settings precedence Local > Project > User); the two tests that encoded the
  old "local-only key is ignored" model are inverted, plus a new
  local-only-enable-with-no-other-scope case.
  (Docs consulted per the fresh-docs mandate:
  <https://code.claude.com/docs/en/settings> scope precedence;
  <https://code.claude.com/docs/en/plugins-reference> `--scope local`.)

## [0.12.0]

### Added

- **Opt-in git `commit-msg` hook — tool-agnostic convention enforcement (audit f1
  depth layer, f4 backstop).** New `/guardrails:setup apply install-commit-msg`
  action installs `lib/git-hooks/commit-msg-convention.sh` (plus a copy of the
  enforcement resolver) into the operator's personal `.git/hooks/`, validating the
  subject of EVERY commit in the repo — editor commits, `git commit -F <file>`,
  IDE integrations, humans outside Claude — against the same team-tracked pattern
  the CC-layer gate reads. Trust-surface contract:
  - **Never runs from bare `apply`** — only the explicit `install-commit-msg`
    argument writes anything, and only the two guardrails-owned files in the
    operator's own hooks dir. `core.hooksPath`, hook-manager configs, and tracked
    files are never touched; the committed team lane is deliberately not
    scaffolded (a human PR decision — and `core.hooksPath` changes are the exact
    shape `block-no-verify` refuses).
  - **Chain-or-refuse:** managed repos (`core.hooksPath`, lefthook, husky,
    pre-commit) → refuse with the manager-side remediation; an existing
    `commit-msg` hook is never overwritten — chain (renamed to
    `commit-msg.pre-guardrails`, run first, its rejection final) or refuse.
  - **Sentinel-marked** (`guardrails-commit-msg-convention`) so
    convention-inference tooling excludes the installed hook as a signal
    (echo-cycle guard); sentinel-marked re-install is idempotent ("refreshed").
  - **Unresolved = no enforcement** (never the bundled CC default); resolver
    removed → fail open, never block blind; `fixup!`/`squash!`/`amend!` subjects
    exempt (autosquash); a chained pre-existing hook's rejection is final.
  - **Deadlock-by-design exit:** the rejection message instructs fixing the
    subject and never suggests `--no-verify` (which `block-no-verify` refuses in
    Claude sessions anyway); in-session the CC-layer gate blocks first, making
    this hook the cross-tool backstop.
  15-case contract suite (`lib/git-hooks/commit-msg-convention.test.sh`).

## [0.11.0]

### Added

- **`block-convention-violation` — the CC-layer content gate (audit f4).** A ninth
  guard validating the DECLARATIVE convention where a team has explicitly tracked
  one: the commit subject of the canonical stdin form (first non-empty line of the
  Bash heredoc / PowerShell here-string body) and the `gh pr create --title` value
  are checked against the POSIX-ERE pattern resolved from the consumer's tracked
  `.claude/source-control.md` by the vendored enforcement resolver
  (`resolve-convention-pattern.sh`, synced from `lib/` — the commit-convention
  seam, `docs/conventions/commit-convention/`). Contract highlights:
  - **Unresolved = no enforcement.** No team-tracked pattern, a non-ERE pattern, or
    an unreadable config → the gate no-ops; it never blocks against the bundled
    Conventional Commits default.
  - **Never blocks `gh pr create` itself** — only a present-and-violating
    `--title`/`-t` value; the documented inline fallback stays usable.
  - **Inherits `block-noncanonical-commit`'s exemption taxonomy** — `--amend`,
    `-C`/`-c`, `--fixup`/`--squash`, `-F <path>`, and an in-progress
    merge/rebase/cherry-pick/revert are never content-gated.
  - **Declared bypass coverage:** `gh pr edit --title`, `--fill`, direct API
    calls, babysit retitles, and non-heredoc stdin producers
    (`printf … | git commit -F -`) are out of scope, documented in the hook
    header.
  - Kill switch: `block_convention_gate_enabled` userConfig (default true).
  Matched on `Bash|PowerShell` like the sibling git guards; PowerShell commands
  reduce through the bundled classifier first, so unparsable PS never reaches a
  content decision here (the mechanic gates own those).

## [0.10.3]

### Fixed

- **Git/commit guards are no longer bypassed via the PowerShell tool.** The
  `block-no-verify`, `block-noncanonical-commit`, `block-dangerous-git`, and
  `flag-commit-pr-skill-bypass` guards matched only the `Bash` tool, so the same
  `git commit --no-verify` ran unblocked through Claude Code's opt-in PowerShell
  tool (`CLAUDE_CODE_USE_POWERSHELL_TOOL=1`) — a bypass proven live on Windows.
  Their PreToolUse matchers are now `Bash|PowerShell`, and a bundled classifier
  (`lib/powershell/ps-command.sh`) reduces a PowerShell command to a
  Bash-tokenizer-faithful form or fails closed: the canonical PowerShell commit
  form (a here-string piped to `git commit -F -`) is allowed exactly as the Bash
  `-F -` form is, while a PowerShell command carrying a construct the Bash
  tokenizer cannot faithfully parse (backtick, `--%`, `(`/`)`/`{`/`}` grouping,
  an unbalanced here-string, a dynamic invocation — `iex`/`invoke-expression` or a
  call/dot-source of a string literal — or a process launcher / nested shell:
  `Start-Process`/`saps`, `pwsh`/`powershell`/`cmd`) is refused unless it is
  provably git-free. The refusal is decided by whether the command could reach git
  at all — recovering backtick obfuscation (`` g`it com`mit `` → `git commit`),
  reading quoted command words and launched argv, and treating an opaque run
  string as possibly-git — never by trusting a negative `commit`/`push` shape
  match on a scan the obfuscating construct has already mangled (the fail-open
  class fixed in #740/#903). Because the sink keys on git-presence,
  `block-dangerous-git` fails closed on ANY git-shaped unparsable PowerShell — not
  only commit/push — so an obfuscated `git reset --hard` / `clean -fd` /
  `checkout` cannot slip through, and its block message names those destructive
  forms rather than the commit form.
- **`block-hook-bypass` now covers the PowerShell file-write surface.**
  `Set-Content`, `Add-Content`, `Out-File`, `Tee-Object` (including the `ac` and
  `tee` aliases and backtick-escaped names), `New-Item -Value` (alias `ni`), the
  `Export-*` serialize-to-file family (alias `epcsv`), `[IO.File]::WriteAll*`/
  `AppendAll*` and StreamWriter, `iex`/`invoke-expression` (opaque run string,
  failed closed), and content-producer `>`/`>>` redirects (echo/Write-Output/
  Write-Host, a string or here-string literal, or a `$variable` value) that bypass
  the Write/Edit hook gate are blocked on the PowerShell tool. Producer-scoped like
  the Bash detection (a tool's own output redirect — e.g. `git diff > out.txt` — is
  still allowed; `New-Item -ItemType Directory` with no `-Value` is not a content
  write). `sc` is matched only in its unambiguous Set-Content form (a `-Value`/
  `-Path`/`-LiteralPath`/`-Stream` parameter): it is Set-Content's alias in Windows
  PowerShell 5.1 but sc.exe in PowerShell 7, so a genuine `sc query` service call
  stays allowed. Scope: this closes the write-GATE bypass; secret-pattern and
  hardcoded-path CONTENT scanning of PowerShell writes remains on the
  `Write|Edit`-matched guards (deferred).
- **Review round 4 (post-restack bot findings, all within-parity holes of covered
  constructs):** the `.exe`-suffixed launcher spellings (`cmd.exe /c git …`,
  `powershell.exe -Command …`) and the `start` alias of Start-Process now reach the
  fail-closed launcher sink; the `write` alias of Write-Output counts as a redirect
  producer; module-qualified writer spellings
  (`Microsoft.PowerShell.Management\Set-Content`) match the writer cmdlets; a
  parenthesized redirect producer (`('secret') > f`, `(Write-Output x) > f`) is
  unwrapped and judged by what it produces (a grouped tool run stays allowed); and a
  call/dot-source of a QUOTED writer name (`& 'Set-Content' …`,
  `& 'Invoke-Expression' …`) is detected on the quote-intact text before blanking. A
  quoted path to an arbitrary program (`& 'C:\tools\x.exe'`) stays allowed — the
  same quoted-command-word residual the Bash guard carries.
- **Review round 5 (computed-expression shapes fail closed):** a launcher whose
  program is a computed expression or variable (`Start-Process ('g'+'it') …`,
  `saps $tool …`, optionally behind one named parameter) is treated as
  possibly-git rather than provably git-free; a call/dot-source of a computed
  target (`& ('Set-'+'Content') …`, `& $w …`) fails the write gate closed the
  same way iex does; and an expression-literal redirect producer (`36 > out.txt`,
  `[char]65 > out.txt` — spaced value writes, not attached-digit stream
  redirects) counts as a content write.
- **Review round 6:** a quoted string merely ending in the characters `@'`/`@"`
  (`Write-Output '@'`) no longer reads as a here-string opener — paired quote
  spans are stripped before the opener test, so following code lines cannot be
  swallowed into a phantom body; backslash path separators normalize to forward
  slashes in the reduced command so a path-qualified `C:\Git\cmd\git.exe reset
  --hard` tokenizes to basename git (a safe `…\git.exe status` stays allowed);
  the call/dot-source probes and both write-gate call checks accept a
  statement/block separator boundary (`;& …`, `{& …}`), not only whitespace;
  and every stream's producer cmdlet (`Write-Error … 2>`, `Write-Warning … 3>`,
  verbose/debug/information) counts as a redirect content write.
- **Review round 7:** fd-dup merge redirects (`2>&1`, `*>&1`) strip before
  segment splitting, so a tool capture (`git status 2>&1 > out.txt`) is no
  longer cut into a phantom numeric segment and wrongly blocked (over-block
  regression from round 5); invoked script blocks unwrap like parenthesized
  producers (`& { Write-Output secret } > f` blocks, `& { git diff } > f`
  stays allowed); and `.exe`-suffixed git spellings normalize in the reduced
  command so the POSIX hook matches the basename too (`C:\Git\cmd\git.exe
  reset --hard` blocks on a Linux-run hook, not only under msys).
- **Review round 8:** a module-qualified redirect producer
  (`Microsoft.PowerShell.Utility\Write-Output secret > f.txt`) compares by
  cmdlet basename, closing the last spelling gap in the producer head check.
- **The PowerShell coverage bar is documented as Bash-parity, not airtight.** These
  guards are accidental-destruction friction, not a boundary against deliberate
  evasion — and the Bash guard they extend does not stop deliberate evasion either.
  The PowerShell surface is held to what the Bash guard already sees through
  (`sh -c`/`bash -c` → `pwsh`/`powershell -Command`; `nice`/`sudo`/`env` →
  `Start-Process`), no higher. Beyond-parity vectors are shared Bash+PS residuals,
  not covered: a command word supplied entirely by an unexpanded variable
  (`& $tool commit`, `iex $var`), deep nested-shell / `cmd /c` quoting, .NET
  reflection beyond the common `[IO.File]`/StreamWriter writes, and any shell
  variable / command substitution.

### Changed

- **Guard block messages are shell-agnostic.** `block-noncanonical-commit` shows
  the PowerShell here-string form when the call originates from the PowerShell
  tool (not a Bash heredoc), and `block-hook-bypass`'s remediation no longer
  assumes Bash.

## [0.10.2]

### Changed

- **`--config-env` git aliases for a guarded subcommand are now refused by SHAPE, not
  resolved (`#740`).** `--config-env=<key>=<envvar>` names an environment variable that
  holds the alias expansion; that value can be fed from an ambient variable, an inline or
  `env` command-line prefix, an `export` (including `set -a`, an `export NAME` promotion,
  or an assignment-prefixed `export`), or a nested `bash -c` / `!`-alias in any enclosing
  wrapper. Every attempt to resolve the value — to decide whether `git <alias>` runs a
  guarded operation — reopened a fail-open as reviewers found new propagation paths. Since
  the `--config-env=alias.<sub>=<envvar>` option and the `<sub>` it defines always sit in
  the same git invocation, the guards no longer read the value at all: an alias for the
  INVOKED subcommand whose last definition on the command line is `--config-env` is blocked
  structurally (`hook::git_alias_expansion`). Nobody legitimately defines a commit or reset
  alias this way on a guarded invocation — the canonical form is a gitconfig alias or the
  plain subcommand — so the shape alone is sufficient, and the whole env-resolution attack
  surface is removed rather than backstopped.
- **Inline `-c`/`--config` aliases are unchanged.** Their expansion is literally present
  and bounded, so both guards resolve and re-check it as before — last value wins,
  case-insensitive key match, and `!` shell-alias / git-alias expansions re-parsed one
  level deep.
- **The `alias.<sub>.command` subkey is now classified as an alias definition too
  (`#740`).** git reads both `alias.<sub>` and its `alias.<sub>.command` subkey as the
  alias for `<sub>` (`git -c alias.rh.command='reset --hard' rh` runs it); the classifier
  previously matched only the plain spelling, so a dangerous alias smuggled through
  `.command` — via `-c` or `--config-env` — was treated as a non-alias and ran unchecked.
  Both spellings are now detected. Because which spelling git runs when both are set is
  git-version-dependent, the classifier does NOT mirror git's cross-spelling precedence; it
  fails closed on the MAX-DANGER UNION — the last value WITHIN each spelling decides that
  spelling, then the guard refuses if EITHER is `--config-env`-shaped and re-checks EVERY
  inline spelling, blocking if any resolves to a guarded operation and allowing only when
  both spellings are benign. On a git where a benign later `.command` genuinely overrides a
  dangerous plain alias this over-blocks, which is fail-safe.
- **Removed the env-value-resolution machinery** that existed only to read a `--config-env`
  value and the environment feeding it: `hook::snapshot_env` / `HOOK_ENV_SNAPSHOT`,
  `hook::git_effective_config_values` / `HOOK_GIT_CONFIG_UNRESOLVED`,
  `hook::git_reparse_shell_alias` with its shell-alias env inheritance
  (`HOOK_GIT_ENV_INHERITED`), `hook::shell_track_persistent_env` / `HOOK_SHELL_VARS`, and
  `HOOK_GIT_ENV_ASSIGNMENTS`. `hook::git_resolve_index` walks env-assignment prefixes only
  to locate the git token, never to collect their values.
- **Behavior change for `--config-env` aliases.** A `--config-env` alias for the invoked
  subcommand now blocks even when the named variable holds a harmless value — the value is
  never consulted. Still allowed (decidable safe without reading a value): a `--config-env`
  that sets a NON-alias key, one that defines an alias for a subcommand that is not
  invoked, and one whose LAST value for the key is an inline `-c`/`--config`.
- **The shape refusal fires at every alias-recursion depth (`#740`).** A wrapping inline
  alias whose expansion is itself a `--config-env` alias for the invoked subcommand
  (`git -c alias.rh='--config-env=alias.foo=AV foo' rh`, which git runs) previously slipped
  through: the refusal was gated behind `HOOK_NO_ALIAS`, which suppressed it at recursion
  depth ≥ 2. The value-blind `--config-env` shape refusal is now ungated so it fires at
  every depth; only the one-level inline-alias re-expansion remains bounded by
  `HOOK_NO_ALIAS`.

## [0.10.1]

### Fixed

- **`hardcoded-path-check` no longer scans when no project is active.** The
  scope guard previously fell through and scanned unconditionally when
  `CLAUDE_PROJECT_DIR` was unset — contradicting the README's "only police
  files under `$CLAUDE_PROJECT_DIR`" contract — and the gitignore escape hatch
  was gated on the same variable, so in exactly that case the one documented
  per-file exemption was unreachable (real incident: forced `~/` rewrites onto
  a machine-local `~/.gitconfig` edited from a no-project session). The hook
  now skips entirely with no active project: a no-project target is
  machine-local, not the portable repo artifact this guard protects.
  Deliberately different from `secret-pattern-detection`, which scans even
  without a resolvable root — secrets are dangerous anywhere. README "Consumer
  seams" bullets updated to state the no-project behavior explicitly.
  (Official hooks reference consulted per the fresh-docs mandate:
  <https://code.claude.com/docs/en/hooks> — `CLAUDE_PROJECT_DIR` is "the
  project root", with no guarantee of presence in no-project sessions.)

## [0.10.0]

### Added

- **`statusMessage` declared on every hook's `hooks.json` handler** (9 handlers)
  and **telemetry added to `workflow-resilience-check`**, which previously
  emitted none — it now emits at every meaningful outcome (no-fan-out /
  already-throttled / advisory finding), matching every sibling guardrails
  hook (hook-observability convention, `docs/conventions/hook-observability/`).

### Fixed

- **Missing-`jq` degraded state is now user-visible.** `block-dangerous-git`,
  `block-hook-bypass`, `block-no-verify`, `block-noncanonical-commit`,
  `cli-flag-verify`, `flag-commit-pr-skill-bypass`, `hardcoded-path-check`,
  `secret-pattern-detection`, and `workflow-resilience-check` previously wrote
  their jq-missing notice to stderr on an exit-0 path — per the official Claude
  Code hooks reference, exit-0 stderr is discarded entirely and was never shown
  to the user or Claude. Each now routes through the shared `hook::require_jq`
  helper (once-per-session `systemMessage` + `additionalContext`, matching the
  fleet's formatter-hook convention). `cli-flag-verify`'s separate
  bundled-verifier-missing path (install corruption) gets the same treatment,
  previously fully silent (not even stderr).
- **`scripts/check-silent-skips.sh` tightened**: a bare `>&2` write no longer
  satisfies the gate's visibility requirement (it never actually satisfied the
  doctrine — exit-0 stderr is invisible; the gate's own assumption was wrong).
  The 9 hooks above were the only fleet sites relying on that leniency.

## [0.9.8]

### Fixed

- **`hardcoded-path-check` pre-filter no longer fails open on the broadened
  checkout roots.** 0.9.7 widened the detailed drive-letter bodies to accept
  `Projects` and `Dev` (both capitalizations), but the cheap `scan_text`
  pre-filter gate still tripped only on `Users|/home/|repos`. Content whose
  sole machine path used a widened root (e.g. `C:\Projects\…`, `C:\Dev\…`)
  early-returned before the detailed scan ever ran — a fail-open in a security
  gate. The gate now lists every root token the detailed bodies accept, keeping
  it a strict superset; a `Projects`-root regression test guards it.

### Changed

- **`block-no-verify` guard description broadened to match shipped behavior.**
  The `block_no_verify_enabled` userConfig description still enumerated
  "lefthook disables" only; it now states the actual configurable default set
  (lefthook, husky, pre-commit, simple-git-hooks).

## [0.9.7]

### Changed

- **`block-no-verify` hook-manager bypass detection is now configurable and
  covers more managers by default.** The env-var disable check matched only
  `lefthook*`, silently missing `HUSKY=0` and other managers. It now resolves a
  configurable prefix set (`block_no_verify_hook_manager_prefixes` userConfig)
  defaulting to `lefthook, husky, pre_commit, simple_git_hooks`; consumer values
  are reduced to identifier characters before use, so a value can never inject
  regex metacharacters.
- **`hardcoded-path-check` machine-path detection broadened past `repos`.** The
  drive-letter-anchored checkout-parent pattern matched only `X:\repos\…`, so a
  hardcoded `C:\Projects\…` or `C:\Dev\…` path went undetected. It now also
  matches `Projects` and `Dev` (both capitalizations); a consumer's own checkout
  root was and remains caught by the driver's project-root literal scan.

## [0.9.6]

### Fixed

- **`flag-commit-pr-skill-bypass` advisory now honors user-global plugin
  enablement.** The `source_control_enabled` probe read only the consuming
  project's `.claude/settings.json` (plus its local override), so when
  source-control was enabled solely at user-global scope (`~/.claude/settings.json`)
  — a common install — the probe false-negatived and the `gh pr create` advisory
  never fired. Enablement now resolves across user-global, project, and local
  scopes in Claude Code's precedence order (user-global base, project overrides,
  local overrides), matching how the platform actually merges `enabledPlugins`.

## [0.9.5]

### Fixed

- **`block-hook-bypass` no longer fails open when the redirect target is quoted.**
  The producer-scoping narrowing dropped a quoted redirect TARGET along with inert
  quoted prose, leaving the segment as `echo x >` with no surviving operand — so
  the file-write check saw no target and `echo x > "$out"`, `echo x > 'out.txt'`,
  and `printf y > "$file"` wrote real files while returning 0. A quoted span that
  belongs to a redirect-operand word (the word began right after a `>`) is now kept
  as literal content instead of dropped, so the write signal survives the strip;
  partial quoting (`echo x > "$dir"/out.txt`) is covered too. Keeping the literal
  content preserves the `/dev/null` exemption (`echo x > "/dev/null"` stays
  allowed), so the fix adds no false positive, and a quoted span anywhere else
  (prose, a `--body "…"` payload, a quoted echo argument) still drops.
- **`block-hook-bypass` no longer false-fires when an `echo`/`printf` token and a
  `>` redirect merely co-occur in one Bash command.** The `echo > file` heuristic
  matched any command string containing both tokens, so capturing a subprocess's
  stdout to a scratchpad data file (`bash fetch.sh 526 > pr526.json && echo
  "EXIT: $?"`), a bounded poll loop with a status `echo`, or a `gh issue create
  --body "…"` whose text merely mentions the tokens were all blocked. The check is
  now producer-scoped: it splits the literal-stripped command into simple-command
  segments and flags only a segment whose command word is `echo`/`printf` AND that
  redirects stdout into a real file — so the redirect's producer must be the
  echo/printf, not a co-located but unrelated one. It correctly fires inside loop,
  conditional, and brace-group bodies (`for …; do echo x > f; done`). The
  literal-strip now also carries an open quote across physical lines, so a
  multi-line quoted argument (a `--body "…"` payload spanning newlines) stays
  inert instead of leaking its tokens from the second line on. `printf … > file`
  content-authoring is now caught alongside `echo … > file`.
- **The producer scan now peels command prefixes, so a producer hidden behind a
  valid shell prefix is no longer a trivial bypass.** The head-only producer match
  looked only at a segment's first token, so `FOO=bar echo x > file`,
  `command echo x > file`, `builtin printf x > file`, and `env echo x > file` all
  slipped through even though their stdout is redirected into a real file — the
  prior anywhere-in-command detector caught them. The segment head now peels
  environment assignments and the command-name modifiers `command`/`builtin`/
  `exec`/`env` before the echo/printf check, closing that hole. Peeling is
  block-safe: the producer gate still requires echo/printf, so revealing a
  non-producer command word never causes a block. External command-runner
  utilities that carry their own options (`nohup`/`nice`/`time`/`timeout`/`sudo`/
  `xargs`, non-bare `env`) remain an accepted, documented floor.
- **An fd-duplication redirect before the stdout redirect no longer splits the
  producer off from its `> file`.** Segmenting on every `&` cut `echo x 2>&1 >
  file` and `echo x >&2 > file` at the dup's `&`, orphaning the trailing stdout
  redirect so neither blocked. The `&` in a redirect (`>&`, `<&`, `&>`) is now
  protected from the control-operator split, so the simple command stays one
  segment and its `> file` is scanned as the echo's own; `&&` and a background
  `&` still split as separators.
- **Compound-command headers and pipeline negation before a producer are now
  peeled.** `! echo x > file`, `if echo x > file; then …`, and the `while`/`until`/
  `elif` forms wrote the file yet slipped past the head-only match, since only
  `do`/`then`/`else`/`{` were peeled. The header set now also peels
  `if`/`elif`/`while`/`until`/`!`, completing the before-command keyword class.
- **An unmatched quote inside a `#` comment no longer leaks a quote span onto the
  next line.** `strip_literals` carries an open quote across physical lines, so an
  unclosed `"` in a trailing comment (`true # "`) previously stripped the following
  line's real producer as a quoted span, and `true # "` + newline + `echo x > file`
  returned 0. An unquoted `#` at a word boundary (line start, or after a blank or
  one of `;|&()<>`) is now dropped to end-of-line WITHOUT touching the quote state,
  so the comment cannot leak a span. A mid-word `#` (`echo a#b > file`) and a
  parameter expansion (`${v#x}`) stay literal, so those real writes still block.
- **A leading redirection before the command word no longer hides the producer.**
  Bash permits redirections before the command word, so `> real.txt echo x` writes
  the file, yet the segment-head producer match (anchored at `^(echo|printf)`) never
  saw it and returned 0. A leading redirect is now peeled (operator + its target
  word) to expose the producer, while the redirect itself stays in the segment so
  `_echo_file_out`/`_echo_devnull` still decide whether a real write exists — a
  leading input redirect or `/dev/null` discard stays allowed.
- **The bare `coproc` header before a producer is now peeled.** `coproc echo x >
  file` writes the file but `coproc` was absent from the peeled header set, so it
  returned 0. `coproc` is added to the command-header peel. Only the bare keyword is
  peeled; the named form `coproc NAME { … }` remains a documented floor (NAME is
  indistinguishable from a command word by prefix-peeling, and its redirect is
  group-level — the same brace-group floor).
- **Options of the `command`/`exec` modifiers are now peeled too.** Both were
  peeled but their options were not, so a producer behind a valid option leaked:
  `command -p echo x > file` and `exec -a name echo x > file` wrote the file yet
  returned 0. The producer scan now also peels the modifier options documented by
  bash built-in help (`command [-pVv]`, `exec [-cl] [-a name]`, and a `--`
  end-of-options marker), consuming the value word of the argument-taking
  `exec -a name` so the echo/printf behind it is still seen. Option peeling applies
  only to `command`/`exec` — `env`/`builtin` keep their bare-only floor. As an
  exception, `command -v`/`-V` DESCRIBE their argument instead of running it, so
  `command -v echo > file` (which writes the word "echo", not echo's output) stays
  allowed — the guard blocks only a genuine echo/printf producer.
- **Backslash-escaped separators no longer split a producer from its redirect.**
  The segment split treated an escaped separator as a command boundary, so
  `echo x \; > file` and an escaped-newline continuation (`echo x \` + newline +
  `> file`) — both a single simple command in bash that writes the file — landed
  the producer and its `> file` in different segments and returned 0. Escaped
  separators (`\;`, `\|`, `\&`, `\(`, `\)`, and an escaped newline) are now
  protected from the split so the simple command stays one segment.

## [0.9.4]

### Fixed

- **`cli-flag-verify` scans only the content the tool call wrote, never the whole file
  from disk.** The PostToolUse check re-read the entire edited file, so any edit to a
  file already containing an unrecognized flag elsewhere re-fired the advisory about
  lines the edit never touched. The hook now scans the tool payload — an Edit's
  changed hunk, a Write's full content (a PostToolUse Write payload cannot distinguish
  a new file from an overwrite, so whole-content is the closest the payload allows) —
  per the hook-precision convention's diff-scoping rule. Repro-first: the
  pre-existing-flag stay-quiet case fails against the prior hook and passes now, with
  a hunk-introduced-flag MUST-FIRE counterpart. Markdown fence state is derived from
  the hunk alone — a fence-straddling edit can misclassify in either direction, the
  accepted trade of hunk scoping. A partial-replacement edit whose hunk is a bare
  flag fragment (no binary in the changed region) reconstructs bounded on-disk
  context — the lines carrying the hunk's flag tokens — so a swapped-in unknown flag
  still fires, while a pre-existing unrelated flag sharing that line stays quiet.

## [0.9.3]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.9.2]

### Fixed

- **`hardcoded-path-check` no longer hard-denies every absolute path under a home-rooted
  project.** The repo-path branch matched `PROJECT_ROOT` as a bare substring with no
  context gate, so a session rooted at the user home flagged any real path under it
  (`AppData\...`, `Desktop\...`) as a checkout-root leak. The branch now engages only
  when the resolved project root is a real git checkout that is neither the home
  directory nor one of its ancestors; a missing home resolution leaves the branch
  active (fail toward detection). Adds the branch's first MUST-FIRE regression case
  plus two stay-quiet repros (non-git home project; checkout equal to home). The
  sibling percent-env false positive lives in the upstream-owned pattern library and
  ships separately via the standards distribution.

## [0.9.1]

### Fixed

- **`cli-flag-verify` now buffers stdin via `hook::buffer_stdin` instead of reading fd0
  directly.** It was the last hook entry script whose stdin parse ran `jq` against the
  inherited, unbounded fd0 — `hook::read_file_path` — leaving it exposed to the Windows
  Win32-pipe late-EOF stall the [0.8.0] migration closed for every other hook. The payload
  is now buffered once through the bounded `read -t` helper and piped into
  `hook::read_file_path`. As an advisory hook it skips silently on any read failure — empty
  stdin (rc 1) and read timeout (rc 2) alike — matching its advisory siblings
  `flag-commit-pr-skill-bypass` and `workflow-resilience-check`.

## [0.9.0]

### Added

- **`block-noncanonical-commit` — `git commit` must pipe its message via `-F -`.** The advisory that
  previously covered this was overridden 11 times in a single session; an advisory that is always
  overridden trains the reader to filter it out. The guard enforces the *mechanic*, not the ritual:
  `git commit -m "<multi-line>"` flattens newlines unpredictably across shells, and the stdin form is
  what prevents it. Exempt, because no message-on-stdin form exists for them and gating them would
  strand real work: `--amend`/`--no-edit`, `-C`/`-c`/`--reuse-message`/`--reedit-message`,
  `--fixup`/`--squash`, `-F <path>`, and any commit taken while a merge, rebase, cherry-pick, or
  revert is in progress. Kill switch `block_noncanonical_commit_enabled`; allow-list
  `block_noncanonical_commit_allow` (`message-flag` permits a bare `-m`). Detection reuses the
  argv-grammar-faithful parser, so `bash -lc` wrappers resolve and a commit body merely *mentioning*
  `git commit -m` never fires. Aliases are expanded before the subcommand verdict — inline `-c`
  (last value wins, as git applies it) and aliases persisted in git config alike — closing the hole
  where `git c -m x` reads as subcommand `c` and walks straight through. `--config-env` aliases are a
  documented residual: the shared parser stores their value undifferentiated from `-c`, so the
  environment variable *name* arrives in place of the expansion (tracked separately). `git -C <path>` is honored when probing sequencer state, so a conflict
  resolution driven at another repo reads that repo's state rather than the session cwd's.

### Fixed

- **`flag-commit-pr-skill-bypass` no longer demands `--trailer`.** The old condition required both
  `-F -` **and** `--trailer`, but `/commit` omits the trailer when the resolved `trailer_policy` is
  `none` — so in a repo whose convention forbids a co-author trailer, the skill's own conformant
  output was flagged on every commit. The trailer is policy; only the stdin form is mechanic. This
  also had to be settled before the new guard could block on the same condition: requiring
  `--trailer` to pass would have permanently blocked `/commit` in that configuration.

### Changed

- **`flag-commit-pr-skill-bypass` is now `gh pr create`-only.** The `git commit` branch moved to
  `block-noncanonical-commit`, so the two never double-fire on one command. `gh pr create` stays
  advisory and cannot become otherwise: `/pull-request create` issues that exact command itself, and
  [anthropics/claude-code#22655](https://github.com/anthropics/claude-code/issues/22655) (expose
  `skill_name` to hooks) is closed as not planned — a hook cannot tell a skill-driven call from an
  ad hoc one, so blocking it would deadlock the skill.

## [0.8.0]

### Changed

- All seven hook entry scripts read stdin via the shared `hook::buffer_stdin` helper
  (bounded `read -t`, default 2s) instead of a bare `cat`, so a Windows Win32-pipe
  late-EOF stall can no longer hang a hook — and with it every tool call — indefinitely.
- **Blocking guards now fail closed on a stdin read timeout.** When `hook::buffer_stdin`
  returns 2 (the read timed out before a complete JSON payload arrived), the five
  blocking guards (`block-dangerous-git`, `block-hook-bypass`, `block-no-verify`,
  `secret-pattern-detection`, `hardcoded-path-check`) exit 2 with the BLOCKED reason on
  stderr instead of skipping: a guard that could not evaluate the tool call must not
  wave it through. Empty stdin still skips, matching the previous empty-payload
  behavior. The two advisory hooks (`flag-commit-pr-skill-bypass`,
  `workflow-resilience-check`) skip on any read failure, as before.

## [0.7.1]

### Fixed

- **`flag-commit-pr-skill-bypass` jq-absent skip is now visible** (prerequisite-visibility
  doctrine). The hook previously no-op'd silently when `jq` was missing; it now writes the
  same one-line stderr notice its sibling guardrails hooks emit ("advisory disabled —
  install jq to enable") before exiting 0.

## [0.7.0]

### Added

- **`/guardrails:setup` skill on the uniform contract** (fleet conformance
  wave, dim 8). `check` reads the guard scripts and `hooks.json` as the
  source of truth and probes Bash 5.0+, `jq` (absence = every guard fails
  open — surfaced as the FAIL it is), each guard's effective toggle, the
  `cli-flag-verify` scan surface, and the `block-dangerous-git` allowlist.
  `apply` is guidance-only with no write path; reconfiguration guidance
  states `--config`'s fresh-install-only semantics. All-toggles-disabled
  downgrades prerequisite FAILs to INFO.

## [0.6.2]

### Changed

- Header comment ordering in `machine-path-patterns.sh` corrected to the `shell=bash` →
  description → pragma → code convention: the `SC2034` disable and its rationale comment now
  sit immediately before the pattern definitions they guard, instead of ahead of the module
  description. Comment-only change; pattern bodies are unchanged.

## [0.6.1]

### Changed

- **Per-OS machine-path regex bodies sourced from a shared, standards-managed file.** The five
  `HPP_*` pattern bodies (`HPP_WIN_USER_BODY`, `HPP_MACOS_USER_BODY`, `HPP_LINUX_USER_BODY`,
  `HPP_WIN_REPO_BODY`, `HPP_ESCAPED_WIN_REPO_BODY`) — previously a hand-synced copy of the same
  bodies carried by `ci-workflows`' `machine-specific-paths` action and `medley`'s
  `tools/shared/path-detection` — now live in `machine-path-patterns.sh`, the org's
  standards-managed materialization (`melodic-software/standards#172`). `hardcoded-path-patterns.sh`
  sources it and keeps only its own scan wrapping (OS-context suppression, exclusion pipes).
  Patterns are byte-identical to the prior inline copy; no behavior change.

## [0.6.0]

### Added

- **`block-dangerous-git` guard** (PreToolUse on Bash, blocking): stops irreversible git operations
  before they run — `push --force`/`-f` (never `--force-with-lease`), the equivalent
  leading-`+` refspec and `--mirror` force-push forms (a push dry-run disarms), `reset --hard`,
  `clean` with a force flag (a dry-run flag anywhere disarms the check — git honors it regardless
  of order), worktree-wide `checkout`/`restore` pathspecs (`.`, `:/`, exclude-only sets, and
  long-form magic carrying `top`; path-scoped forms and index-only `restore --staged .` pass), and
  forced `checkout -f`/`--force` and `switch -f`/`--discard-changes` (both throw away local
  modifications). Accepted unique-prefix abbreviations of the blocked long options match too
  (git parse-options accepts them: `reset --h` runs `--hard`). The parse-cap fail-closed path
  never consults the allow-list. `branch -D` is deliberately not blocked: deleted refs are
  reflog-recoverable and sanctioned skill flows issue it inline. Per-repo/per-user allow-list via
  the `block_dangerous_git_allow` userConfig option (comma list of `push-force`, `reset-hard`,
  `clean-force`, `checkout-dot`, `restore-dot`, `checkout-force`); kill switch the
  `block_dangerous_git_enabled` userConfig option set to false. Capability adapted from
  mattpocock/skills `git-guardrails-claude-code`; the implementation is the house argv-grammar
  parser, whose word-exact matching avoids upstream's substring false-blocks (all `git push`
  blocked; `checkout .github/…` matching `checkout .`).

### Changed

- The argv-grammar tokenizer, git-executable resolver, and subcommand walk that `block-no-verify`
  carried privately moved into the shared hook-utils library (`hook::bash_parse_segments`,
  `hook::git_resolve_index`, `hook::git_resolve_subcommand`) so both git guards share one parser.
  `block-no-verify` behavior is unchanged with one alignment: the `core.hooksPath` block now applies
  exactly to `git commit` / `git push` (its documented scope) instead of firing on any git
  subcommand mid-walk.

## [0.5.1]

### Changed

- Shared `hook-utils.sh` resynced with the fleet's new prerequisite-visibility
  helpers (jq-free notice emitters, once-per-session gate, jq gate). No
  behavior change for this plugin's guards: their documented jq fail-open with
  a stderr notice is unchanged.

## [0.5.0]

### Changed

- **Per-hook kill switches and tuning scalars migrated to native `userConfig`** (the
  fleet-wide kill-switch doctrine ruling). Each guard's toggle is now a `userConfig`
  boolean named `<guard>_enabled` (default `true`), read by the hooks through the
  native `CLAUDE_PLUGIN_OPTION_<KEY>` hook-process mirror; `cli-flag-verify`'s binary
  set and skip list are now the `cli_flag_verify_bins` / `cli_flag_verify_skip_bins`
  options. Configure interactively with `/plugin configure guardrails` or headless via
  `claude plugin install --config KEY=VALUE`.
- **BREAKING:** the `HOOK_<NAME>_ENABLED`, `HOOK_CLI_FLAG_VERIFY_BINS`, and
  `HOOK_CLI_FLAG_VERIFY_SKIP_BINS` environment variables are retired and no
  longer read. A consumer that set any of these in a
  settings `env` block must re-express the value as the matching `userConfig` option.
  Zero-config behavior is unchanged (all guards on, same defaults). The
  `HOOK_TELEMETRY_SINK` consumer-side telemetry seam is unaffected.
