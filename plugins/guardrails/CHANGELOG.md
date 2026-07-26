# Changelog

All notable changes to the `guardrails` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.16.4]

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
    `git -C <dir> rev-parse --show-toplevel` — supplies both the `!` body's base
    and the canonical repository identity in the shell-alias cycle key, so the
    guard tracks git's behavior on every platform by construction. Identity also
    canonicalizes for free: `-C .`, `link/..`, a subdirectory, and every other
    spelling of one repository collapse to a single key, which is what stops a
    self-rewriting `-C` chain. Resolution failure **fails closed**, scoped to the
    alias walk only, so an ordinary `git commit -F -` resolves nothing and forks
    nothing (measured: 0 git subprocesses; the `-C .` chain stops after 4, not the
    128 traversal budget; a 20-hop inline chain still forks 0).

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

  - **A `!` body's launch directory is no longer assumed to be the work-tree top
    level** (`block-noncanonical-commit`; review finding on the fix above). git's
    chdir into the top level is CONDITIONAL: `setup.c`'s `setup_explicit_git_dir`
    performs it only when the invocation's directory lies inside the located work
    tree, returning from its `cwd outside worktree` branch without one. So
    `git --git-dir=<r>/.git --work-tree=<r> -c alias.a='!…' a` invoked from OUTSIDE
    `<r>` launches the body where the caller stands — verified on git
    2.54.0.windows.1, where that invocation prints the caller's directory while the
    same one run from `<r>/sub` prints `<r>`. Taking the top level unconditionally
    therefore aimed the directory-dependent probes at a directory the command never
    touches: with a merge staged under `<r>/child`, `!git -C child commit -m x` read
    that child's sequencer state, took the in-progress-merge exemption and returned
    0, while the commit really landed in `<r>`, where no merge was running (verified
    fail-open, and `main` blocks the same payload — the regression was this change's
    own). The identity probe now carries `--is-inside-work-tree` beside
    `--show-toplevel`, on the same single fork: git's own answer to the condition
    `setup.c` tests, so the guard still asks rather than models containment. The top
    level is adopted as the body's base only where git would actually chdir there;
    otherwise the body keeps the caller's composed directory. The shell-alias cycle
    key stays on the canonical identity either way, so the collapse that stops a
    self-rewriting `-C` chain is unchanged.

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
  repository's top level (canonical twin allowed), a symlinked-parent `-C link/..`
  fixture gated on the platform actually resolving through the symlink (asserted on
  POSIX, skipped loudly on Windows, where git is itself textual), `-C ./././.`
  collapsing to a cycle without a `.`-cancelling pass, `-C sub/..` reaching a
  `commit -m` (blocked) beside its canonical twin (allowed, which is why `..` is
  not refused outright), six launch-directory cases staging an in-progress merge in
  exactly one candidate directory so the verdict names which one the guard read
  (caller outside the named work tree, caller inside it, and `--git-dir` with no
  `--work-tree`), and benign controls (safe multi-hop chain allowed; alias cycle, self-
  and mutually referential persisted shell aliases terminate and allow without
  hanging). Closes #964.

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
