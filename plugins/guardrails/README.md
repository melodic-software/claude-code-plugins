# guardrails

A Claude Code plugin bundling fourteen **safety guards** that catch risky agent
actions the moment they happen, before a write lands or a bash command runs.
Each guard is independently toggleable, so you run exactly the subset you want.

## Contents

- [The guards](#the-guards)
  - [Enforceability tiers](#enforceability-tiers)
  - [Scope notes](#scope-notes)
- [Per-hook kill switches](#per-hook-kill-switches)
- [Consumer seams](#consumer-seams)
- [Telemetry (opt-in)](#telemetry-opt-in)
- [Requirements](#requirements)
- [Install](#install)
- [Configuration](#configuration)
  - [Options reference](#options-reference)
  - [How to set these](#how-to-set-these)
  - [Upstream documentation](#upstream-documentation)
- [License](#license)

## The guards

Since **0.31.0** the always-on guards are registered through one dispatcher per event,
`hooks/run-guards.sh`, which reads the payload once, extracts its fields with one `jq`
process, and sources each guard in turn inside that one bash process. The table below
still names every guard, and every guard still ships as its own script with its own
contract test, kill switch, and telemetry envelope, deciding exactly as it did as a
standalone hook. `hooks/hooks.json` lists each guard by file name as an argument of the
dispatcher line for its event, so the registration stays readable per guard. What the
dispatcher owns: the spawn shape (one hook process per Bash/PowerShell call where there
were eight, one per Write/Edit PreToolUse where there were three, one per Write/Edit
PostToolUse where there were three), the exit code (2 if any guard blocks, and every
guard still runs so a command that trips two guards shows both reasons), and the merge
of several guards' `additionalContext` into the one JSON document a hook process may
emit. The [hook budget accounting](#hook-budget-accounting) carries the measurement.
`workflow-resilience-check` is not always-on and is registered on its own.

| Guard | Event / matcher | Behavior | What it catches |
|-------|-----------------|----------|-----------------|
| **secret-pattern-detection** | PreToolUse · Write \| Edit \| NotebookEdit **and** `mcp__github__push_files` \| `mcp__github__create_or_update_file` | **Blocks** (exit 2) | High-confidence secret/credential patterns (AWS/GitHub/GitLab/Slack/Stripe/OpenAI keys, PEM private keys) in new file content. Since **0.32.0** also in content bound for a GitHub repository through an MCP write, where there is no local file to fix afterwards and no pre-commit hook on the path. |
| **hardcoded-path-check** | PreToolUse · Write \| Edit \| NotebookEdit **and** `mcp__github__push_files` \| `mcp__github__create_or_update_file` | **Blocks** (exit 2) | Hardcoded machine-specific paths: Windows drive-letter homes, macOS/Linux user homes, machine-specific repo checkout roots. Since **0.32.0** also on the GitHub MCP write lane, which catches the session's own checkout path leaking into pushed content. |
| **block-no-verify** | PreToolUse · Bash \| PowerShell | **Blocks** (exit 2) | Git hook-bypass attempts on `git commit` / `git push`: `--no-verify` / `-n`, `core.hooksPath=` assignment, and hook-manager disable env vars, a configurable prefix set defaulting to `lefthook`, `husky`, `pre_commit`, `simple_git_hooks` (e.g. `LEFTHOOK=0`, `HUSKY=0`, `PRE_COMMIT_*=false`), tunable via `block_no_verify_hook_manager_prefixes`, including inside compound `cd … && …` commands. |
| **block-dangerous-git** | PreToolUse · Bash \| PowerShell | **Blocks** (exit 2) | Irreversible git operations: `push --force`/`-f` plus the equivalent leading-`+` refspec and `--mirror` forms, and the unsafe `--force-with-lease` spellings, in the two kinds git itself treats differently. **No expected value** (bare `--force-with-lease` or `=<refname>`) leases against the remote-tracking ref, which git documents as "trivially defeated" by a background fetch, blocked unless `--force-if-includes` is present, which git documents as the mitigation for exactly this form. **A movable `=<refname>:<expect>`**, such as `origin/main`, `HEAD`, a tag, an *abbreviated* object id, or hex of the wrong width for this repository's hash format, all of which git resolves at push time, and gitrevisions resolves a short hex word as a ref before trying it as an object-id prefix, is blocked unconditionally, because git declares `--force-if-includes` a no-op alongside an explicit `:<expect>`. A lease passes only when `<expect>` is immutable: a **literal** object id of the pushed repository's own hash width (detection never evaluates substitutions, so resolve it with `git rev-parse` as a separate step and pass the result) (40 hex under SHA-1, 64 under SHA-256, read from `git rev-parse --show-object-format` with the command's own `-C`/`--git-dir`/`--work-tree`/`--namespace` replayed onto it; undeterminable fails closed) or the empty string asserting the ref must not exist. The other width is a ref name there, not an object id. git ignores a ref whose name is full-width hex for its own format, but resolves one of the other width like any name. git scopes a pin to its own ref, so a bare fallback alongside a pinned entry still governs every other ref being updated; where the same ref carries several lease entries, git consults the first, and so does this guard. A trailing `--no-force-with-lease` cancels every previous lease, and a push dry-run disarms the check. Also blocked: `reset --hard`, `clean` with a force flag (any dry-run flag disarms), worktree-wide `checkout`/`restore` pathspecs (`.`, `:/`, `:(top…)`; path-scoped forms and `restore --staged .` pass), and forced `checkout -f` / `switch --discard-changes`. Accepted unique-prefix abbreviations of the blocked long options match too. `branch -D` is deliberately not blocked (reflog-recoverable; sanctioned skill flows issue it). Per-repo/per-user allow-list via the `block_dangerous_git_allow` userConfig option (comma list, any subset of `push-force,push-lease-unsafe,reset-hard,clean-force,checkout-dot,restore-dot,checkout-force`). |
| **block-hook-bypass** | PreToolUse · Bash \| PowerShell | **Blocks** (exit 2) | Bash file-write workarounds that circumvent the Write/Edit hook gates: `cat > file`, `echo … > file`, inline python code with file-write indicators (`python`/`python3`/`py`/`pypy`, with `-c` or reading the program from stdin as `python3 - <<PY`), and a same-command staged write whose effective redirect target is reused as an `mv`/`cp` source toward a non-scratch destination. Executable-token detection ignores quoted prose/commit text that merely mentions the pattern. |
| **block-windows-drive-tmp** | PreToolUse · Bash \| PowerShell **and** Write \| Edit \| MultiEdit \| NotebookEdit | **Blocks** (exit 2) | Windows-only: write targets that are a drive-root temp path: POSIX `/tmp`, MSYS `/c/tmp`, `C:\tmp`, or drive-root `\tmp`, which resolve to `<drive>:\tmp` instead of `%TEMP%` and accumulate at the volume root. On the **command lane** redirects and write utilities (`mkdir`/`mktemp`/`tee`/`cp`/`Set-Content`/`Out-File`/…) are blocked; on the **file-path lane** (since **0.30.0**) the tool's own `file_path` / `notebook_path` is matched directly, because on a Write the path *is* the write target. Both lanes call one matcher, so the same spellings block and the same ones pass. Does not fire on non-Windows hosts; leaves `%TEMP%` / `$TEMP` / `$TMPDIR` / `$env:TEMP` / `/var/tmp`, relative `./tmp`, `foo/tmp`, `/tmpdir`, `C:/tmp2` and UNC `\\server\tmp` alone. |
| **block-exported-msys-pathconv** | PreToolUse · Bash \| PowerShell | **Blocks** (exit 2) | Windows-only: an **exported** `MSYS_NO_PATHCONV` / `MSYS2_ARG_CONV_EXCL` (also the `declare -x` / `typeset -x` spellings), which switches off MSYS argv rewriting for every *later* command in the same command string. A later path argument then reaches a Windows-native program unconverted and git resolves its leading `/` against the current drive, so `git worktree add /d/worktrees/x` creates `<current-drive>:\d\worktrees\x` (#2870). Deliberately keys on the environment, not on a path shape: the incident command's path argument was identical to one that had already worked. A prefix whose command word is a **shell** (`MSYS_NO_PATHCONV=1 bash -c '…'`, `env … sh -c '…'`) blocks too: the prefix scopes to one *process*, and when that process is an interpreter, one process is every command inside it. A prefix on a **non-shell** command word (`MSYS_NO_PATHCONV=1 git show …`) and a bare assignment are not matched. The first scopes to exactly that command, and the second has no effect at all because the MSYS runtime reads the environment. Does not fire on non-Windows hosts. |
| **cli-flag-verify** | PostToolUse · Write \| Edit, dispatcher `if`-gated to `.md`, `.sh`, `.bash`, `.ps1`, `.psm1` | **Advisory** (exit 0) | Hallucinated CLI flags: a `--flag` written as a command that does not exist in the binary's actual `--help` output. Surfaces via `additionalContext`, never blocks. |
| **workflow-resilience-check** | PreToolUse · Workflow | **Advisory** (exit 0) | Un-throttled Workflow fan-out: a script calling `parallel()` / `pipeline()` with no wave-cap throttle (`inWaves` / `inWavesPipeline`) and no retry wrapper (`agentRetry`), which risks a burst 529 under wide Opus fan-out. Surfaces a resilience checklist via `additionalContext`, never blocks. **Opt-in. Default off since 0.20.0** (behavioral-class injector config-disabled per #2021; set `workflow_resilience_check_enabled=true` to enable). |
| **block-noncanonical-commit** | PreToolUse · Bash \| PowerShell | **Blocks** (exit 2) | `git commit -m` whose message actually contains a newline. A multi-line `-m` flattens newlines unpredictably across shells; pipe it via `-F -` / `--file -` instead (narrowed in 0.20.0 per #2021: single-line `-m`, bare `git commit`, and repeated single-line `-m` paragraphs all pass). On the PowerShell tool a here-string `-m` value blocks too. Its content is uninspectable and multi-line by construction of the form. Exempt: `--amend`, `-C`/`-c`/`--reuse-message`/`--reedit-message`, `--fixup`/`--squash`, `-F <path>`, and any commit taken while a merge/rebase/cherry-pick/revert is in progress. Resolves `bash -lc` wrappers and git aliases (inline `-c` and persisted config alike). |
| **block-convention-violation** | PreToolUse · Bash \| PowerShell | **Blocks** (exit 2) | A commit subject or `gh pr create --title` that violates the team-tracked convention pattern declared in `.claude/source-control.md`. No tracked pattern means no enforcement. Same exemptions as `block-noncanonical-commit`. |
| **flag-commit-pr-skill-bypass** | PreToolUse · Bash \| PowerShell | **Advisory** (exit 0) | Any `gh pr create`, bypassing this marketplace's own `/source-control:pull-request create` skill. Only fires when the consuming project's own `.claude/settings.json` enables the `source-control` plugin, and is silent otherwise. Surfaces via `additionalContext`, never blocks. **Opt-in. Default off since 0.20.0** (behavioral-class injector config-disabled per #2021; set `flag_commit_pr_skill_bypass_enabled=true` to enable). |
| **skill-reference-verify** | PostToolUse · Write \| Edit, dispatcher `if`-gated as above, the guard itself scans `.md` only | **Advisory** (exit 0) | A `` `/plugin:skill` `` reference in markdown that does not resolve. Only fires inside a marketplace repo, and only for a plugin that repo's own manifests own. A reference to another marketplace is left alone. Resolves through manifest and frontmatter `name`, so a renamed directory still matches. Surfaces via `additionalContext`, never blocks. |
| **stale-path-verify** | PostToolUse · Write \| Edit, dispatcher `if`-gated as above, the guard itself scans `.md` only | **Advisory** (exit 0) | A repo-relative path cited in a markdown inline code span that this repo's own history shows was **deleted** and that is gone from the working tree. The gate is provenance, not absence: the exact path must appear in `git log HEAD --no-renames --diff-filter=D --name-only`, so a path belonging to a consuming project's tree, an example, or a plan is never adjudicated. Names the surviving file when exactly one tracked path now carries that basename. Link destinations are out of scope. Surfaces via `additionalContext`, never blocks. |

The nine blocking guards feed their stderr message back to Claude as
actionable fix guidance. The five advisory guards surface their findings the same
way but always allow the operation.

### Enforceability tiers

Twelve guards are **deterministic**. Their oracle is a mechanical test with no
judgment step. Two are **detect-then-judge**, where the oracle is mechanical but
the conclusion is a human verdict, never an auto-fix: `skill-reference-verify`,
because globbing a plugins tree is exact only inside a marketplace repo that owns
the referenced plugin; and `stale-path-verify`, because a path may be cited
deliberately as a deletion or completion record and be correct exactly as
written. `cli-flag-verify` is deterministic in its oracle but advisory in its
action, because a written claim can be deliberately forward-looking.

`stale-path-verify` detects **staleness, not hallucination**. An invented path was
never in the repository, so it never enters the deleted-path set and the guard
stays silent by construction. Separating a hallucinated path from a correctly
documented consumer-tree path needs a signal a repo-root oracle does not have.
Both are absent locally and conventionally shaped, so that class is deliberately
out of scope until such a signal exists.

### Scope notes

- **Hook-manager coverage.** `block-no-verify` recognizes the disable env-var
  prefixes of a configurable manager set: `lefthook`, `husky`, `pre_commit`,
  and `simple_git_hooks` by default (`LEFTHOOK=0`, `HUSKY=0`, `PRE_COMMIT_*=false`,
  `SIMPLE_GIT_HOOKS=0`, …). Extend or narrow it with the
  `block_no_verify_hook_manager_prefixes` userConfig option (see Consumer seams).
  Independent of that set, the manager-agnostic `--no-verify` / `-n` and
  `core.hooksPath=` checks catch bypasses regardless of which manager runs the
  hooks.
- **Argv-grammar-faithful matching (and its residual).** `block-no-verify` and
  `block-dangerous-git` share one parser (in the bundled hook-utils library)
  that parses the command the way the shell builds argv, segmenting on
  unquoted operators and tokenizing each segment honoring `'…'`, `"…"`, `$'…'`
  (ANSI-C), and backslash escapes. Flags and pathspecs are matched on parsed
  argv words across quoting, escaping, wrappers (`env -i git …`, `nice git …`,
  `sudo -u x git …`), and git global options (`git -C <dir> commit …`), so a
  `--no-verify` inside a quoted `-m` value stays a message, quoted prose never
  fires, and `checkout .github/x` never matches `checkout .`. The parser does
  **not** evaluate shell variable / command substitution (`$VAR`, `$(…)`,
  `$IFS`). A determined author can construct an expansion-based bypass. An
  inline env prefix (`HOOK_..._ENABLED=false git push -f`) does **not** disable
  a hook. The prefix reaches only the spawned git process; disabling requires
  settings-level env (the settings.json write is the residual trust boundary).
  **These are friction guards against accidental/casual bypass, not a
  sandbox.** (A command longer than 16 KB is not parsed and is blocked
  fail-closed.)
- **`block-dangerous-git` scope boundaries (not bypasses).** Three cases are
  often filed together; only one is a live bypass (#2151 item A, inherited
  `--git-dir`/`--work-tree` in a `!` alias body). The other two are
  **documented limits** of static argv matching:
  - **Shell `cd` relocation.** `cd <other-repo> && git push …` runs the
    push from a directory no `-C`/`--git-dir` names. Evaluating it requires
    arbitrary shell word expansion, which this guard deliberately does not
    do.
  - **False block from a non-repository base.** When the session root is
    not itself a repository, a shell `cd` into a repo and a pinned
    `--force-with-lease` can be blocked because the width probe cannot
    resolve a repository at the guard's computed base. That is fail-closed
    scope, not a bypass.
- **A NUL byte in the payload blocks, whatever the command says.**
  `block-no-verify` and `block-dangerous-git` refuse any payload whose read
  fields carry a NUL, before they look at the command at all, including one
  that leaves no command text behind. The reason is that the text a guard can
  read is not dependably the text that would run: two behaviours were measured
  and they disagree. bash **discards** a NUL while parsing a command it reads,
  and Node's `child_process` **refuses** a NUL-bearing string outright.
  Which of them, if either, a hook payload reaches has not been traced. Refusing
  is the one verdict correct under all of them, and needs no such trace. A NUL is
  treated as malformed input rather than as an exotic-but-valid command.
- **`block-hook-bypass` string-matching floor.** Detection strips quoted literal
  spans before matching the executable token, so quoted prose or a commit
  message merely mentioning `cat >` / `python3 -c open(...)` is not flagged. The
  accepted residual: a write inside a command substitution in double quotes
  (`echo "$(python3 -c 'import pathlib …')"`) is **not** caught. The strip
  treats the quoted span as inert. Same friction-guard, not-a-sandbox posture as
  `block-no-verify`.
- **`block-hook-bypass` inspects one command string, and only the write forms
  listed above.** It reads `.tool_input.command`; it does not read the contents
  of a script that command invokes, so `bash build.sh` runs whatever writes
  `build.sh` performs. It is also producer-scoped by design, so a redirect whose
  producer is another program (`sort f > out`, `curl … > page.html`, `cat a b >
  c`) is allowed. Only a content producer writing a real file
  (`cat > f` consuming stdin, `echo`/`printf > f`, inline python writes,
  the PowerShell write cmdlets, including `Tee-Object` and its `tee` alias on the
  PowerShell tool) is blocked. The python lane matches the interpreter FAMILY
  (`py`, `python`, `pypy`, with an optional version suffix: `py -c`, `python -c`,
  `python3.11 -c` are the same write as `python3 -c`), and since **0.28.0** it also
  covers a program read from stdin with an explicit `-` (`python3 - <<PY … PY`);
  `python3 <<PY` with **no** `-` is an accepted residual, because matching a bare
  trailing interpreter token would block `cat script.py | python3`. On the **Bash**
  tool, **`tee` / `tee -a` and inline writes via other interpreters (`node -e`,
  `perl -e`, `ruby -e`, `sed -i`, `dd of=`, `awk >`, …) are accepted residuals**,
  outside the modeled surface, not oversights. A **same-command staged write**
  (`jq . f > /tmp/x && mv /tmp/x <repo-file>`) is blocked since **0.28.29** when the
  effective redirect target is reused as an `mv`/`cp` source toward a destination
  outside configured scratch roots (path-identity keeps ordinary renames
  unblocked). Residuals that lane still cannot see: cross-tool-call staging,
  variable-carried paths, quoted/opaque move sources, and other movers
  (`install`, `rsync`, `dd`). Note the consequence either way: any Bash-side write
  these residuals allow also skips the `Write|Edit`-matched content guards
  (secret patterns, hardcoded paths), so those guards are defense-in-depth, not a
  sandbox. Content invariants that must hold are enforced write-path-independently
  by the opt-in git `pre-commit` content-invariants hook
  (`/guardrails:setup apply install-pre-commit-content`) or an equivalent CI check.
  The block message carries a lane-specific scope note so a reader does
  not credit the guard with coverage it never claimed.
- **`block-hook-bypass` isolated-session remedy.** Write or Edit may be refused
  for paths in the main checkout when the agent is in an isolated session or
  worktree. That is not a dead end: write under a configured
  `block_hook_bypass_scratch_roots` directory, or ask the operator for a
  session-scoped disable via `claude --settings`. The user-global
  `block_hook_bypass_enabled` switch is last resort. It persists across every
  repository where guardrails is enabled. Those levers are printed on stderr
  (Claude Code surfaces an exit-2 stderr reason; `systemMessage` is an exit-0
  field and is discarded on a block).
- **Every hook says so when it could not run.** A hook has three outcomes,
  not two: allow (exit 0), block (exit 2), and could-not-run. Every registered
  hook and the dispatcher install the shared abort boundary
  (`hooks/abort-boundary.sh`, #3528) right after their first line. It passes
  the statuses the hook chooses through untouched and turns any other exit (an
  unbound variable under `set -u`, a helper that stopped existing, a
  `hook-utils.sh` that failed to load) into a one-line "guard did not run"
  notice naming the hook and the status, on stderr and as a
  `systemMessage` / `additionalContext` document, then exits with the posture
  the hook declares beside its install. Every hook currently declares
  **fail-open**: the tool call proceeds exactly as it did before this boundary
  existed, and the notice is the only change. Before it, such an abort exited
  with a bare status, usually 1, which Claude Code treats as a non-blocking
  error with nothing to show; a blocking guard enforced nothing and nobody was
  told. Flipping a hook to fail-closed (deny the call when the guard could not
  check it) is the one word `closed` on its install line; the contract test
  reads the registered set from `hooks.json`, so a hook added without the
  boundary fails it.
- **`block-hook-bypass` fails open on its own crash.** The boundary above is
  the generalization of the handler this guard carried first (#3130 F5): an
  internal script error exits 0 so a defect on this hottest-path hook cannot
  freeze the session, with the dual-channel notice so the allow is not silent.
  Stdin timeout and a NUL payload still fail closed. The 60s `hooks.json`
  `timeout` on this handler is a harness-level fail-open the plugin does not
  override: if the process is killed at that bound, the tool call proceeds.
- **`block-hook-bypass` option parse is strict.** Only the exact strings `true`
  and `false` are accepted (`unset` defaults to enabled). Any other value keeps
  the guard enabled and names the bad value. A typo must not silently disable
  a blocking safety control.
- **`block-hook-bypass` does not see MCP-provided shell or file-write tools.**
  The matcher is `Bash|PowerShell`. A write issued through an MCP tool is an
  accepted residual, same class as the unmonitored Bash forms above. The two
  CONTENT guards are the exception since **0.32.0** — see the next note.
- **The content guards cover the GitHub MCP write lane; the scope is exactly two
  tools.** `secret-pattern-detection` and `hardcoded-path-check` inspect
  `mcp__github__push_files` (every entry of its `files` array, not just the
  first) and `mcp__github__create_or_update_file`. This closes a real hole: a
  `Write|Edit` matcher does not see an MCP write, so a session could be cleared
  by these guards and still push the same secret to a repository by another
  route, where there is no local file to fix afterwards and no `pre-commit`
  layer on the path.

  **`mcp__github__delete_file` is deliberately NOT covered.** Its schema carries
  `owner`, `repo`, `path`, `message` and `branch`, and no content. There is
  nothing for a content guard to scan, and a delete cannot introduce a secret or
  a hardcoded path. Listing it would claim coverage that consists of skipping
  every call.

  Three local-only gates are deliberately not applied on this lane, because an
  MCP write names `owner/repo` and a repo-relative path and has no local file:
  the project-scope guard (a relative path is never under `CLAUDE_PROJECT_DIR`,
  so applying it would skip every MCP write — a silent hole, not a scope), the
  git-working-tree requirement, and `git check-ignore` (which answers what THIS
  checkout ignores, not the destination repo). The path ALLOWLIST is the same
  list, asked of the repo-relative path: an `.env.example` or a test fixture
  tree is the same false positive whichever route writes it.
  `hardcoded-path-check` still resolves its scan root, which is the most
  valuable half of the lane — it catches this machine's own checkout path
  appearing verbatim in content being pushed.
- **`block-hook-bypass` ships one scratch root exempt, and takes more by
  configuration.** Since **0.32.0** the guard exempts the host temp trees, which
  the harness's own per-session scratchpad sits under. It is gated on
  `CLAUDE_PROJECT_DIR` naming a project root **outside** the temp tree: with no
  project root it does not fire, and when the project root is itself temp-rooted
  a temp file is project content, so the default stands down. It is not spelled
  as a static default, because it has no fixed spelling — the scratchpad path
  carries a session id — so it resolves at run time.

  **Exempting it gives up no protection**, which is the only reason a default is
  defensible here: `hook::read_file_path`, the entry every `Write|Edit` content
  guard reads its file through, already declines a temp-tree file from a non-temp
  project, so those targets were never reachable by the gates this guard exists
  to protect. Before 0.32.0 they blocked anyway, which cost false positives with
  no true positive.

  **The memory tier is deliberately NOT a second default.** `<memory_dir>/`
  (default `.work/`) was exempted here during review and removed again, because
  the argument above does not carry to it: `secret-pattern-detection` scans a
  `Write` to `.work/notes.md` today, so exempting Bash redirects there would let
  `printf '<secret>' >> .work/notes.md` reach disk unscanned while the identical
  `Write` stayed blocked — the same content-guard bypass the MCP lane above
  exists to close. The consequence is that `printf '*' >> .work/.gitignore`
  still blocks; that command is `session-flow`'s own documented procedure, so the
  conflict routes to the skill (use `Write`, which is scanned) rather than to this
  guard.

  **The default is confirmed through symlink resolution before it grants.** The
  lexical compare alone would exempt a redirect on its spelling, so a symlink
  under an exempt root pointing into the repository (`/tmp/to-repo -> <repo>`)
  would let `echo <secret> > /tmp/to-repo/tracked.py` through while the identical
  direct path blocked. The configured roots document that as a residual on the
  ground that an operator naming a root accepts that root's contents; a shipped
  default has no operator to accept anything, so it resolves the target (or its
  nearest existing ancestor) and re-checks containment before exempting. Cost
  stays on the grant path only: the lexical test runs first, so a command that was
  going to block spends no resolver process. A path with no existing component
  holds no symlink and is exempted on its spelling, which is the same answer
  resolution would give. Residual: the check inherits the axis's case-folding, so
  on a case-sensitive filesystem a symlink whose real spelling carries capitals is
  not resolved and stays exempt.
- **`block-hook-bypass` takes additional target-scoped exemptions by
  configuration.** `block_hook_bypass_scratch_roots` takes a comma-separated
  list of absolute directories whose contents are scratch, a session or job temp
  root, where a throwaway probe file is written that no formatter, secret scanner
  or path check would ever process. The list is empty by default and **adds to**
  the shipped root above rather than replacing it; the kill switch remains
  the whole-guard lever. When set, the match is made on the
  **effective** stdout target (the last redirect wins, as with `/dev/null`) after
  lexical normalization, and containment is decided at a path-component
  boundary: `/tmp/scratchevil/f` is not under `/tmp/scratch`, a `..` escape is
  resolved away before the compare, `echo x > /tmp/scratch/f > real.txt` still
  blocks, and an unexpanded (`$VAR`, `~`) or glob target is never exempt. A
  **relative** target is exempt only when the guard can place it: since
  **0.32.0** it is resolved against the tool call's own `cwd` from the payload,
  and refused outright when the command carries a `cd`/`pushd`/`popd` (which
  moves the directory the redirect resolves against, and whose target this guard
  does not evaluate) or when the payload names no absolute cwd. That is what lets
  `printf '*' >> .work/.gitignore` through while `echo x > src/main.py` and
  `cd /etc && echo x > .work/f` still block. A **quoted or escaped** operand is
  never exempt either, and that one
  fails closed rather than being documented: the quote strip drops a kept
  target's quotes, and the segment split would then read a `;`, `|`, `&` or space
  *inside* the operand as syntax, so `> "/tmp/scratch/a;/../../etc/passwd"`,
  one pathname to bash, would be judged on `/tmp/scratch/a`. Since **0.27.0**
  the operand is **marked** wherever that would happen, so it reaches the compare
  as one word and the decision is made on the whole thing: an operand carrying
  whitespace, `;`, `|`, `&`, `(`, `)`, a newline or a backslash escape exempts
  nothing, and a merely quoted operand is refused by this axis on its shipped
  floor. **Quotes and backslashes elsewhere in the command no longer matter.**
  Before 0.27.0 this test read the whole raw command tail after the first `>`
  *character*, so a quote in an unrelated later segment, or a `>` inside quoted
  content, cancelled the exemption for an earlier plain write. Both were friction
  rather than protection and both are gone. `echo x > /tmp/scratch/f && grep foo
  "notes.txt"` and `echo "a > b" > /tmp/scratch/f` are exempt again. The same
  truncation reached the `/dev/null` discard and predated this option (#2226);
  the same marking closes it, so a quoted `/dev/null` operand carrying a second
  fragment now **blocks** where it was allowed. Two residuals remain, both
  deliberate and both pinned: normalization is lexical, so symlinks out of a
  root are not followed, and the compare is case-insensitive because the segment
  scan runs over the lowercased command. Naming a root is accepting that root's
  contents.
- **`flag-commit-pr-skill-bypass` is a nudge, not a gate.** Detection is a
  literal-stripped top-level regex match, not a full argv-grammar parser. It
  does not evaluate shell variable / command substitution, and a determined
  author can construct a form that evades it. It cannot tell "the skill ran
  this exact command" from "someone hand-typed the same shape", and for
  `gh pr create` there is no command-shape signature at all, so every direct
  call is flagged. It stays advisory and cannot become otherwise:
  `/source-control:pull-request create` issues that exact command itself, so blocking it would
  deadlock the skill being advertised. `create.md` also documents a legitimate
  inline fallback when skill discovery is broken.

- **`block-noncanonical-commit` gates shape, not skill invocation.** No hook can
  see which skill (if any) originated a Bash call, so "did you run `/source-control:commit`" is
  not an available condition, and shape is the better target regardless, since
  it enforces an outcome verifiable in `git log`. It deliberately does not
  require `--trailer`: `/source-control:commit` omits the trailer under a resolved
  `trailer_policy` of `none`, so demanding it would block the skill's own
  conformant output in repos whose convention forbids co-author trailers.

- **`block-windows-drive-tmp` guards two doors with one matcher, and only one of
  them existed before 0.30.0.** A write reaches the drive root either as a
  command string (`echo x > /tmp/f`) or as a tool's own target path (`Write`
  with `file_path: C:\tmp\f`). The hook read `.tool_input.command` only, so the
  second shape hit an empty-`COMMAND` early exit and passed unexamined — a real
  `C:\tmp\tmp.rSFIkHm5DO` was created on 2026-08-30 with no guard firing. Both
  shapes now feed the shipped `has_drive_root_tmp()`; there is no second matcher
  to drift. The file-path lane carries **none** of the command lane's
  string-matching floor, because it needs none: on `Write`/`Edit` the path is
  the write target by construction, so there is no redirect to parse, no
  producer-utility whitelist, and no quoted-prose ambiguity. Its residual is
  narrower than the command lane's and of a different kind: a path assembled at
  runtime and passed by a tool this guard does not match — an MCP file-write
  tool, or a Bash form the command lane's own residuals already allow.
- **`block-windows-drive-tmp`'s file-path lane shipped blocking on a measured
  sweep, per [ADR 0003](../../docs/adr/0003-verification-guards-earn-default-on-by-measured-precision.md).**
  Corpus: 259 distinct `file_path` / `notebook_path` values that a real `Write`,
  `Edit`, `MultiEdit` or `NotebookEdit` actually carried across 227 local Claude
  Code session transcripts on a Windows host — absolute Windows and MSYS paths,
  not the repo-relative ones a drive-root matcher could never match, which is
  what makes a low finding count informative here. **1 finding in 259 (0.39%
  firing), and it was a true positive**: `/tmp/tmp.rSFIkHm5DO/worktree-root`, the
  very write that produced the `C:\tmp\tmp.rSFIkHm5DO` this lane exists to stop.
  Six seeded spellings were detected end to end.

  **What that evidence does and does not support, stated plainly.** Precision is
  1/1, so the ratio is 100% and the sample is one — this is the ADR's
  near-zero-findings branch, where the seeded-detection burden carries the
  argument and the precision figure by itself does not. The corpus is one
  Windows host and one operator, so it is evidence about this deployment and
  weaker evidence about others; it contains no `MultiEdit` or `NotebookEdit`
  entries at all, and those two tools are covered by the contract suite and by
  the shared matcher, not by the sweep. **The ratio considered acceptable for
  this surface is a false-positive rate near zero, and the justification is that
  the cost of a wrong block here is unusually low** — the agent gets a stderr
  line naming `%TEMP%` and reissues the write, which is a second of friction,
  against a missed write that is silent by construction and was found only by
  noticing litter on a volume root days later. The near-misses that would
  falsify the ratio (`%TEMP%` paths, `/var/tmp`, `docs/tmp`, `./tmp`, `foo/tmp`,
  `/tmpdir`, `C:/tmp2`, UNC `\\host\tmp`, and a `tmp` directory under a
  single-letter parent) are pinned as MUST-stay-quiet cases in the contract
  suite. Compare the ADR's shipped reference guard, promoted at 0.51% firing and
  57% precision. Corpus counts are as of 2026-08-31 on the measuring host and
  grow as that host accumulates sessions; the figure that matters is the ratio.
- **`block-windows-drive-tmp` reads the payload's PATH fields, never its
  content.** `.tool_input.content` / `.new_string` / `.new_source` are
  deliberately not requested. `HOOK_JQ_FIELDS_NUL` is computed across every
  requested field, so pulling written content in would make this guard fail
  closed on a NUL anywhere in a file body — that surface belongs to
  `hardcoded-path-check` and `secret-pattern-detection`. A prose mention of
  `/tmp` inside a written file is therefore never a block on this lane. The
  Bash lane is scoped differently but reaches the same place: it sees only the
  command string, and a drive-root path there still has to sit in a
  write-shaped position, so a heredoc body carrying `C:\tmp` inside a
  `cat > file` does not block either.
- **`block-windows-drive-tmp` puts no length ceiling on a file path, and that is
  a decision.** `MAX_COMMAND_LEN` (16384) fails the command lane closed because
  that lane walks its string character by character twice before matching
  anything, so past some length the guard genuinely cannot say what would run.
  The file-path lane runs three EREs over one string with no tokenization: a
  drive-root prefix matches at any length, so length creates no parse ambiguity
  and a blocking ceiling would only refuse legitimate long paths. The payload as
  a whole stays bounded by `hook::buffer_stdin`, whose stall path fails closed.

### Hook budget accounting

**0.32.14, leftover helper-capture forks on verifiers and PreToolUse
telemetry.** 2026-09-06, Linux CI host characterised measurable by
`spawn_probe`. The 0.32.13 tokenizer table is unchanged: this drop is
the leftover `$(hook::repo_root)` / `$(hook::repo_relative_path)` /
`$(hook::normalize_path)` captures the always-on verifiers and
PreToolUse scanners still paid around helpers that already have `_to`
forms. Kernel census `strace -f -e trace=clone,clone3,fork,vfork,execve`:

| Counter | before | after |
|---|---|---|
| `skill-reference-verify` Write with no skill refs | 18 clones (8 execs) | 17 clones (8 execs) |
| `secret-pattern-detection` clean Write | 10 clones (4 execs) | 8 clones (4 execs) |

PATH-visible execs unchanged. Isolation `$(source …)` forks are
unchanged (#3685). Finding text and redaction are unchanged.

*Method.* Kernel trace as above; PATH shim cannot see a builtin-only
fork. GNU Bash runs command substitution in a subshell even for builtins
(Command Substitution, Bash Reference Manual;
https://mywiki.wooledge.org/CommandSubstitution). Cygwin's fork is a
non-copy-on-write Win32 CreateProcess (Cygwin User's Guide, Process
Creation). No wall-clock claim: this host's spawn floor is sub-millisecond
and says nothing about the Windows spawn tax the budget binds to.

**0.32.13, leftover tokenizer and path-helper forks.** 2026-09-06, Linux CI host
characterised measurable by `spawn_probe` (min 0.6 ms, spread 1.32×).
The 0.32.12 PATH-shim and kernel-census tables are unchanged for stdin,
notice, and json-escape: this drop is the command tokenizer every Bash
guard runs, plus `_to` forms of `repo_root` / `repo_relative_path`.
Kernel census `strace -f -e trace=clone,clone3,fork,vfork,execve` on the
library helpers, 5 plain `bash_parse_segments` plus 5 with a `$'…'` word
after 0 warmup (the subject is a builtin):

| Counter | before | after |
|---|---|---|
| `hook::bash_parse_segments` process creations | 15 (1 process-subst clone per parse, plus 1 `$(ansi_c_decode)` per `$'…'`) | 0 |

Slice, notice, and fused stdin `jq` counts are unchanged. Isolation
`$(source …)` forks are unchanged (#3685). Tokenizer argv is
byte-identical.

*Method.* Kernel trace as above; PATH shim cannot see a builtin-only
fork. GNU Bash runs command substitution in a subshell even for builtins
(Command Substitution, Bash Reference Manual;
https://mywiki.wooledge.org/CommandSubstitution). Cygwin's fork is a
non-copy-on-write Win32 CreateProcess (Cygwin User's Guide, Process
Creation). No wall-clock claim: this host's spawn floor is sub-millisecond
and says nothing about the Windows spawn tax the budget binds to.

**0.32.12, leftover stdin and notice forks.** 2026-09-06, Linux CI host
characterised measurable by `spawn_probe` (min 0.6 ms, spread 1.32×).
The 0.32.11 PATH-shim table is unchanged: those counters fire only on
`exec`, and the forks this drop never exec. Kernel census
`strace -f -e trace=clone,clone3,fork,vfork,execve` on the library
helpers, 20 calls after 0 warmup (the subject is a builtin):

| Counter | before | after |
|---|---|---|
| `hook::json_escape` process creations | 60 (20× `tr` exec) | 0 |
| `hook::emit_channels` process creations | 240 | 0 |
| `hook::resolve_read_slice_to 2` process creations | 20 | 0 |
| `hook::notice_once` process creations | 79 | 3 (1 `mkdir` + 1 `find` + harness) |
| `hook::buffer_stdin_to` (5 fires, fused fields) | 20 | 15 |

Slice acceptance is a Bash 4+ version check (CHANGES bash-4.0-alpha:
fractional `read -t`); it creates no TMPDIR file. PATH-visible `jq`
execs on a benign Bash call stay at 1. Notices and skip-notice JSON
are byte-identical.

*Method.* Kernel trace as above; PATH shim cannot see a builtin-only
fork. GNU Bash runs command substitution in a subshell even for builtins
(Command Substitution, Bash Reference Manual;
https://mywiki.wooledge.org/CommandSubstitution). Cygwin's fork is a
non-copy-on-write Win32 CreateProcess (Cygwin User's Guide, Process
Creation). No wall-clock claim: this host's spawn floor is sub-millisecond
and says nothing about the Windows spawn tax the budget binds to.

**0.32.11, fused stdin completeness and field extract.** 2026-09-06,
Linux CI host. The 0.32.10 table still carries two PATH-visible `jq`
execs on a benign Bash call: `jq -e .` (stdin JSON-complete check) plus
the dispatcher's primed `jq_fields`. After: `hook::buffer_stdin_to`
captures the payload in-process (`printf -v`, no command-substitution
subshell) and, when given the prime filters, uses `hook::jq_fields` as
the completeness check, so those two execs are one. Isolation
`$(source …)` forks are unchanged (#3685). Neither guard's decision
changed.

*Method.* Spawn census via a stable PATH shim (`plugins/performance/scripts/spawn-census.sh`),
`HOOK_TELEMETRY_SINK` unset, this repository as cwd. Host `spawn_probe`
characterised as measurable. Wall clock is p50/p95 of 20 samples after 2
warmup.

| Counter | before | after |
|---|---|---|
| `git status --short` PATH-shim spawns | 2 (`2 jq`) | 1 (`1 jq`) |
| `echo hello` PATH-shim spawns | 2 (`2 jq`) | 1 (`1 jq`) |
| Write of in-repo `.md` PATH-shim spawns | 5 (`3 git`, `2 jq`) | 4 (`3 git`, `1 jq`) |

The milliseconds are context on this cheap-spawn host. The durable figure
is the one `jq` process that disappeared. The remaining exec is the fused
payload parse. The three git processes on a Write are the
`hardcoded-path-check` probes previously measured and not folded.

**0.32.10, git probes that cannot change a benign Bash verdict.** 2026-09-06,
Linux CI host. The 0.32.9 table still carries five PATH-visible execs on
`git status --short` (`3 git` + `2 jq`). This entry is the three git
processes: two `git config --get alias.status[.command]` from
`block-noncanonical-commit` (git ignores aliases that hide current builtins,
so those lookups cannot expand `status` to `commit` and can false-block when
a leftover ignored alias names one), and one `git rev-parse --show-toplevel`
from `block-convention-violation` (the convention pair is only needed for a
commit subject or a `gh pr create --title`). After: builtins are not probed,
and the convention pair loads on first need. Neither guard's decision on a
real commit alias (`git ci`, `git qc`) changed. Deprecated builtins stay
probed (`whatchanged`: git.c `DEPRECATED` bit; git 2.51+ honors
`alias.whatchanged = commit`).

*Method.* Spawn census via a stable PATH shim (`plugins/performance/scripts/spawn-census.sh`),
`HOOK_TELEMETRY_SINK` unset, this repository as cwd. Same-session before
is `origin/main` at `5101f5a2` (the two guards only). Host `spawn_probe`
characterised as measurable (min 0.4 ms, spread 2.26×). Wall clock is
p50/p95 of 20 samples after 2 warmup.

| Counter | before | after |
|---|---|---|
| `git status --short` PATH-shim spawns | 5 (`3 git`, `2 jq`) | 2 (`2 jq`) |
| `echo hello` PATH-shim spawns | 3 (`1 git`, `2 jq`) | 2 (`2 jq`) |
| `git status --short` wall p50 / p95 | 58 / 59 ms | 42 / 43 ms |
| `echo hello` wall p50 / p95 | 53 / 55 ms | 41 / 42 ms |
| `git config --get alias.status[.command]` (`bash -x`) | 2 | 0 |
| `git rev-parse --show-toplevel` on `echo hello` (`bash -x`) | 1 | 0 |

The milliseconds are context on this cheap-spawn host. The durable figure
is the three git processes that disappeared. The remaining two execs are
the dispatcher's primed `jq` payload parse and stdin JSON-complete check.
The per-guard `$(source …)` isolation fork is still a function-level fork
the census does not count (#3685).

**0.32.9, `ps-command.sh` parse tax on the Bash dispatcher.** 2026-09-06,
Linux CI host. The 0.32.6 table still carries the remaining five PATH-visible
execs (`3 git` + `2 jq`); this entry does not change that count. `ps-command.sh`
(~41 KB) was sourced on every Bash fire: once in the dispatcher because
`hooks.json` passes `--lib`, and again inside each isolation subshell whose
guard had a file-scope `source` (the include guard is process-local, so a
parent `source` does not spare the forks). `ps::classify_git_command` returns
0 immediately on Bash, so those parses were tax. After: the dispatcher skips
`--lib` when `.tool_name` is `Bash`, and each guard sources the classifier only
inside `if [[ "$TOOL_NAME" == "PowerShell" ]]`. Neither guard's decision
changed.

*Method.* Spawn census via a stable PATH shim (`plugins/performance/scripts/spawn-census.sh`),
`HOOK_TELEMETRY_SINK` unset, benign `git status --short` payload. `bash -x` counts
`source …/ps-command.sh` lines. Wall clock is p50/p95 of 20 samples after 2
warmup on a host `spawn_probe` characterised as measurable (min 0.5 ms, spread
1.78×).

| Counter | before | after |
|---|---|---|
| Counted PATH-shim spawns | 5 (`3 git`, `2 jq`) | 5 (`3 git`, `2 jq`) |
| `source …/ps-command.sh` (`bash -x`) | 5 | 0 |
| Wall p50 / p95 (n=20) | 51.9 / 53.8 ms | 46.8 / 48.1 ms |

The remaining five execs are still the primed `jq` payload parse and the git
probes the classification guards run on a `git` command.

**0.32.6, remaining `dirname`/`sed` execs on the Bash dispatcher.** 2026-09-05,
Linux CI host. The 0.31.1 paired table still carries the pre-cut figures for the
whole Bash dispatcher (52.6 spawn-equivalents); this entry supersedes that
row's counted-exec half. Neither guard's decision changed. Every always-on
Bash guard located `hook-utils.sh` with `source "$(dirname …)"` even after the
dispatcher had already loaded the library, and the dispatcher copied
`hook::jq_fields` through `sed`. Those are PATH-visible execs; the per-guard
`$(source …)` isolation fork is a function-level fork the census does not
count, and is unchanged.

*Method.* Spawn census via a stable PATH shim (`plugins/performance/scripts/spawn-census.sh`),
`HOOK_TELEMETRY_SINK` unset, benign `git status --short` payload, same host as
the wall-clock pass. Wall clock is p50/p95 of 20 samples after 2 warmup on a
host `spawn_probe` characterised as measurable (min 0.5 ms, spread 1.42×).

| Counter | before | after |
|---|---|---|
| Counted PATH-shim spawns | 13 (`7 dirname`, `3 git`, `2 jq`, `1 sed`) | 5 (`3 git`, `2 jq`) |
| `dirname` | 7 | 0 |
| `sed` | 1 | 0 |
| Wall p50 / p95 (n=20) | 70.0 / 73.5 ms | 60.7 / 62.1 ms |

The remaining five execs are the one primed `jq` payload parse and the git
probes the classification guards still run on a `git` command; those were
measured and deliberately not folded earlier (0.31.1).

**0.32.5, the PostToolUse `if` rows.** 2026-09-05, Linux CI host. The three
PostToolUse verifiers accept five extensions between them (`cli-flag-verify` scans
`.md`, `.sh`, `.bash`, `.ps1` and `.psm1`; the other two scan `.md`), and every
other Write or Edit paid the dispatcher's spawn, library load and payload parse only
to early-exit inside each guard. The `Write|Edit` row now carries one handler per
extension, each with an `if` predicate (`Edit(*.md)` and so on; the field holds one
rule, so one row per extension is the documented shape), and Claude Code evaluates
the predicate before spawning: "The hook command only runs if the tool call matches
the pattern" (hooks reference, `if` field, raw `hooks.md` fetched 2026-09-05).
`run-guards.test.sh` pins the predicate set to the union of the verifiers' own
`case "$FILE"` gates, so an extension added to a gate without an `if` row fails the
suite rather than silently never firing.

*Method.* Mean wall time of 15 dispatcher runs per row on an otherwise idle host,
`HOOK_TELEMETRY_SINK` unset, `bash -c :` spawn floor S = 3.2 ms interleaved, real file
text in every payload. The after figure for a non-matching write is not a
measurement of a faster process: no process exists to measure, because the
predicate fails before the spawn. The matching row is unchanged by construction.

| Per tool call | before | after |
|---|---|---|
| PostToolUse `Write` of an in-repo `.txt` (no verifier scans it) | 86.1 ms (26.9 S) | 0 processes |
| PostToolUse `Write` of an in-repo `.md` | 95.8 ms (29.9 S) | 95.8 ms (29.9 S) |

The same audit named `typos-format` and `eol-normalizer` as the other two ungated
PostToolUse rows. Neither takes an `if` predicate: `typos` scans every file type
including extensionless ones, which that plugin's README records as a deliberate
absence of any extension gate, and `eol-normalizer` resolves every path through the
consuming repository's `.gitattributes` with no extension list at all. Their cost on
a `.txt` is work they are meant to do, not a spawn that early-exits.

**0.32.2, the two PostToolUse verifiers.** 2026-09-05, Linux CI host. The 0.31.1
table below still carries the pre-fix figures for `skill-reference-verify` (287.2)
and `cli-flag-verify` (32.0); this entry supersedes those two rows. Neither hook
changed what it checks. `skill-reference-verify` read every plugin manifest through
four processes each before deciding whether the write cited a skill at all, and
`cli-flag-verify` spawned its verifier script to read a cache file it could have read
itself.

*Method.* Mean wall time of 15 runs per row on an otherwise idle host,
`HOOK_TELEMETRY_SINK` unset. Milliseconds, with the spawn-equivalent alongside where the
spawn floor S was measured in the same pass (2.52 ms before, 1.83 ms after; the
host moved between passes, which is why the ratio, not the millisecond, is the
comparable figure). The `cli-flag-verify` probe is a markdown `Write` naming `gh`,
`claude`, `docker` and `kubectl`, three of the four installed, timed on three warm
runs with an `strace -f` pass counting `execve`.

| Row | before | after |
|---|---|---|
| `skill-reference-verify`, a `.md` citing a skill | 642.9 ms (334.8 S) | 63.8 ms (33.8 S) |
| `skill-reference-verify`, a `.md` citing nothing | 47.1 ms | 47.3 ms |
| ` ` the manifest index loop, isolated (74 manifests) | 468.5 ms | 5.2 ms |
| `cli-flag-verify`, warm cache | 119 to 136 ms | 55 to 79 ms |
| `cli-flag-verify`, cold cache (four `--help` calls) | 980.5 ms | 461.6 ms |
| ` ` `execve` per warm run, total / failed | 152 / 88 | 34 / 11 |

The no-reference path was never the cost, and it is unchanged. Of the 88 failed
`execve` before, every one was `env` walking `PATH` for `bash` on behalf of a
`#!/usr/bin/env bash` exec: four verifier spawns plus the telemetry sink, each
failing once per `PATH` entry ahead of `/usr/bin`. The 11 left are the sink's one
walk, which this plugin does not own. The cold-cache figure is host-bound (it is the
four binaries answering `--help`) and halves here only because the verifier's own
setup work shrank; a Windows Git Bash cold run has been reported at over 11 s and
is not reproduced on this host.

**0.32.0, the GitHub MCP write lane.** 2026-09-04, Linux CI host. The lane is a NEW
`hooks.json` row rather than a widening of the `Write|Edit|MultiEdit|NotebookEdit`
matcher, which is the whole point of its shape: an MCP matcher on the existing row
would have put the new tools' cost on every authored write. As a separate row it
fires only on `mcp__github__push_files` and `mcp__github__create_or_update_file`, so
the always-on write path pays nothing for it.

*Method.* Wall time of 20 to 30 dispatcher runs per payload, divided by the run
count, on an otherwise idle host, `HOOK_TELEMETRY_SINK` unset. Absolute
milliseconds rather than spawn-equivalents: this is a same-host before/after on one
machine, and a spawn-equivalent only survives a host change for a spawn-dominated
hook.

| Per tool call | ms |
|---|---|
| `mcp__github__create_or_update_file` (1 file) | 47 |
| `mcp__github__push_files` (2 files) | 72 |

The per-file cost is one `jq` process, on a lane that fires only when a GitHub MCP
write is issued. The single-file tool spends none: its path and content are already
in the dispatcher's primed field set.

*The always-on `Write` path is unchanged, and that took a fix.* Both guards now ask
for `.tool_input.path`, and the dispatcher's cached `hook::jq_fields` is
all-or-nothing per call — one filter it cannot serve sends the whole call to an
uncached `jq`. Measured, that cost two extra spawns on EVERY Write/Edit: 50 ms to
60 ms. Adding the field to `run-guards.sh`'s `PRIME_FILTERS` returns it to the
dispatcher's single primed `jq`, now nine filters instead of eight: 51 ms before,
52 ms after, as the median of three 30-run batches per tree.

**0.31.1, the guard hot path.** 2026-09-02, Windows 11 + Git Bash. The dispatcher
in 0.31.0 cut the number of hook processes; this cut what each guard spends inside
one. Four guards did expensive setup before checking whether the payload could ever
produce a finding, and a fifth re-derived a constant on every command.

*Method.* The two trees are measured PAIRED: the base tree and the changed tree
alternate within each repetition, 3 repetitions of 4 timed trials, each trial
preceded by its own `bash -c :`. The host is shared, and its spawn floor moved from
42 ms to over 100 ms during the work, so measuring one tree fully and then the other
would attribute that drift to the change. Each case gets one plugin-data directory
for the whole case plus a discarded warm-up run, because Claude Code hands a hook the
same plugin-data directory for a whole session. `HOOK_TELEMETRY_SINK` was set, as it
is on this host. Figures are spawn-equivalents (hook wall divided by the same-run
spawn floor); S was 85.5 ms on the base pass and 101 ms on the changed pass.

*Sample.* The `Write` payloads name a file INSIDE the repository. Every Write and
verifier guard early-exits on a path outside the consuming repo, so an out-of-tree
scratch file measures a no-op rather than the guards.

| Per tool call | before | after | delta |
|---|---|---|---|
| PostToolUse `Write` (whole dispatcher) | 368.4 | 79.3 | 289.1 |
| ` ` `skill-reference-verify` | 287.2 | 26.0 | 261.2 |
| ` ` `stale-path-verify` | 33.8 | 24.4 | 9.4 |
| ` ` `cli-flag-verify` | 32.0 | 20.7 | 11.3 |
| PreToolUse `Bash` (whole dispatcher) | 72.8 | 52.6 | 20.2 |
| ` ` `block-convention-violation` | 12.8 | 3.0 | 9.8 |
| PreToolUse `Write` (whole dispatcher) | 38.6 | 28.5 | 10.1 |
| ` ` `secret-pattern-detection` | 15.8 | 10.0 | 5.8 |

All figures are spawn-equivalents. `skill-reference-verify` carried the whole
PostToolUse cost: it built a plugin name-to-directory index from every plugin
manifest, two `jq` processes each and 74 manifests here, before looking at whether
the written content cited a skill at all. Guards this phase did not touch move by up
to 1 spawn-equivalent between the two passes, which is the resolution of every figure
in the table.

*The PreToolUse `Write` line is not a gain.* A second paired pass on a quieter host,
12 trials per tree at a 42 to 47 ms spawn floor, put that delta at -0.9 with the sink
unset, -3.2 with it set, and -1.9 with it set and `CLAUDE_PROJECT_DIR` unset: at or
below zero every time. Two of the three guards on that path are untouched by this
phase and moved by 1.1 and 0.9 in the pass above, which is the same drift. The one
line this phase changed in `secret-pattern-detection` sits inside `emit_tel`, on the
branch taken only when `CLAUDE_PROJECT_DIR` is empty, so a session that sets it never
reaches the change. The other two rows do reproduce: the second pass put PostToolUse
`Write` at 307.5 and 341.9 against the 289.1 above, and PreToolUse `Bash` at 10.1 and
11.5 against 20.2, the pair in each case being the sink unset and the sink set.

**What remains, and why it is not reachable inside this plugin.** PreToolUse `Bash`
is still 52.6 spawn-equivalents against the fleet target of 8. Three things account
for nearly all of it, and none is a guardrails guard:

- **Telemetry, remaining sink dispatch only on the string-field guards.**
  `HOOK_TELEMETRY_SINK` is opt-in. The seven always-on Bash guards that emit
  `{tool,subject,form}` now build that object with `hook::json_str_object_to`
  (0 jq; byte-identical to `jq -nc --arg …` on this host). The envelope was
  already builtin (#3678). What remains on a wired sink is the fire-and-forget
  sink process itself, plus `jq` in the advisory guards that still pass
  `--argjson` findings arrays. The unwired default path is still zero
  telemetry spawns. The 0.31.1 paired figures above were taken before this
  cut and are not re-stated as current.
- **One subshell fork per guard.** Each guard runs in a `$(source ...)` subshell so
  its `exit` and `trap` behave as they do standalone. A guard that does nothing at
  all measures 0.6 to 0.9 spawn-equivalents, which is that fork. Eight guards on the
  Bash path is an irreducible floor of roughly 7 while the dispatcher keeps that
  isolation.
- **Per-guard classification work.** `block-dangerous-git` and `block-hook-bypass`
  parse the command text; that is the check itself, not overhead.

Three further cuts were measured and deliberately not made, because each costs more
in risk or churn than it returns: priming `hook::repo_root` in the dispatcher (worth
about 1 spawn-equivalent per calling guard, against 4 for telemetry on the same
path); replacing the `$(dirname ...)` in every guard's `source` line (the dispatcher
already makes `dirname` a shell function, so what remains is a fork under the noise
floor); and merging `hardcoded-path-check`'s two `git rev-parse` probes, which would
rework a security guard's scope logic to save one process.

**0.31.0, the dispatcher.** Measured with the fleet's hook fan-out harness
(`dotfiles/common/measure-claude-hook-fanout.sh`, one hook process per line, median of
3 runs, benign `git status --short` payload, Windows 11 + Git Bash, 2026-09-02, host
under concurrent agent load). Before: the eight per-Bash-call guards were eight hook
processes summing to **≈ 2,450 ms** (412 / 403 / 362 / 350 / 336 / 311 / 198 / 78 ms).
After: one hook process; `RUN_GUARDS_PROFILE=1` reports the per-guard slices inside it
as ≈ 167 / 163 / 197 / 18 / 233 / 253 / 156 / 37 ms, **≈ 1,220 ms** in total, the
remainder being fork cost, since each guard still runs in its own subshell so that its
`exit` and `trap` behave as they do standalone. That is a halving of the per-Bash-call
CPU cost and a drop from eight process spawns to one; it is still above the
convention's ≤ 1 s typical ceiling on a loaded host, and the remaining remediation is
the guards' own per-call work (the subshell fork itself, and the external programs a
guard spawns on its hot path), not the dispatcher. The per-Write sets fell the same way:
three PreToolUse processes to one, three PostToolUse processes to one.

Per [`docs/conventions/hook-budget/README.md`](../../docs/conventions/hook-budget/README.md)
rule 1, widening an always-on hook's matcher states its measured share of the
fleet budget. `block-windows-drive-tmp` moved from `Bash|PowerShell` to that set
plus `Write|Edit|MultiEdit|NotebookEdit` in **0.30.0**, so the surface that
changed is the **per-`Write` tool call**, whose ceiling is ≤ 1 s typical /
≤ 2 s worst-case.

**Method** (the convention's, unchanged): `EPOCHREALTIME` wall-clock around
direct hook invocation with a benign representative payload — a `Write` of a
short body to an ordinary repo path — sets launched concurrently (`&` + `wait`)
to approximate the harness's parallel dispatch. Windows 11 + Git Bash,
2026-08-30.

**Host condition, stated because it changes how these numbers must be read.**
The measuring host was under heavy concurrent agent load: its `bash -c :` spawn
baseline measured **4,498 ms** against the convention's reference-host **≈ 80 ms**,
roughly 56× slower. Absolute milliseconds from this host are therefore not
comparable to the convention's figures. Every measurement below re-measures
`bash -c :` **interleaved with each trial** and reports the load-normalized
ratio (hook wall ÷ same-trial spawn baseline); the reference column converts
that ratio back at 80 ms. The spawn-equivalent figure is the stable one.

| Measured (n=12 interleaved trials) | spawn-equivalents | @ 80 ms reference host |
| --- | --- | --- |
| `block-windows-drive-tmp` alone, one `Write` payload | 6.31 | ≈ 505 ms |
| guardrails per-`Write` PreToolUse set BEFORE (2 hooks, concurrent) | 12.59 | ≈ 1,007 ms |
| guardrails per-`Write` PreToolUse set AFTER (3 hooks, concurrent) | 12.34 | ≈ 987 ms |

**The hook's own cost is the measurement that holds: ≈ 6.3 spawn-equivalents,
≈ 505 ms of reference-host work per `Write`.** The set rows are reported for
completeness and must not be read as a delta, because they do not resolve one —
`AFTER` measures *lower* than `BEFORE`, and adding a hook cannot make a set
faster. A separate **paired A/B** (n=15, BEFORE and AFTER launched back to back
inside each trial in alternating order so load drift biases both arms equally)
came out at a mean **1.26×**, but its per-trial ratios span **0.55×–1.82×** —
several trials put AFTER *faster* than BEFORE, which is physically impossible
and is the host's noise, not the hook's cost. **On this host the set-level delta
is below the noise floor and this accounting does not state one.** What can be
said: the harness dispatches matching hooks in parallel, so the set wall is the
max of its members rather than their sum, and a member costing ≈ 505 ms joining
a set already walling at ≈ 1 s cannot raise that wall by more than its own cost
and will usually raise it by less. A re-measurement on a quiet reference host is
the way to replace this bound with a number, and is the honest follow-up.

**Share of the budget, and the overage.** The convention's ceiling is
≤ 1 s typical / ≤ 2 s worst-case **per tool call, counting `PreToolUse` and
`PostToolUse` together for one matcher** — so the surface this widening lands on
is larger than the table above measures: guardrails also runs three `PostToolUse`
verifiers on `Write|Edit`, and the fleet's binding accounting for the whole
per-`Write` set is **≈ 1.9 s** (two formatters plus three guardrails verifiers),
already over the typical ceiling before this change and deeper into overage than
the PreToolUse-only slice measured here suggests. Against that surface the
guard's own **≈ 505 ms is ≈ 25% of the ≤ 2 s worst-case ceiling as an upper
bound on its contribution**, and less than that in practice because it is
dispatched in parallel rather than added. Per the convention's rule 2 the budget
does not relax to absorb the overage: remediation is guardrails' own
spawn-reduction work (#1403), and this change pays part of its way — it removes
the `printf | tr` fork-and-exec pair from the shared normalizer and stops
resolving the telemetry subject in a subshell when no sink is wired, both costs
the pre-existing per-Bash-call lane was paying on every call. Operators who
cannot afford the addition have the per-hook kill switch below.

## Per-hook kill switches

Each guard is toggled by its own `userConfig` boolean, default **on**, except the two
behavioral-class advisories `workflow-resilience-check` and `flag-commit-pr-skill-bypass`, which
have been default **off** since 0.20.0 per #2021. Set a switch to `true` to opt in, or to `false`
for a clean no-op. This per-hook
control is the bundle's core contract: disable one guard without touching the
others.

| Guard | Option |
| ----- | ------ |
| secret-pattern-detection | `secret_pattern_detection_enabled` |
| hardcoded-path-check | `hardcoded_path_check_enabled` |
| block-no-verify | `block_no_verify_enabled` |
| block-dangerous-git | `block_dangerous_git_enabled` |
| block-hook-bypass | `block_hook_bypass_enabled` |
| block-windows-drive-tmp | `block_windows_drive_tmp_enabled` |
| block-exported-msys-pathconv | `block_exported_msys_pathconv_enabled` |
| block-noncanonical-commit | `block_noncanonical_commit_enabled` |
| block-convention-violation | `block_convention_gate_enabled` |
| cli-flag-verify | `cli_flag_verify_enabled` |
| skill-reference-verify | `skill_reference_verify_enabled` |
| stale-path-verify | `stale_path_verify_enabled` |
| workflow-resilience-check | `workflow_resilience_check_enabled` |
| flag-commit-pr-skill-bypass | `flag_commit_pr_skill_bypass_enabled` |

Set them interactively with `/plugin configure guardrails@<marketplace>`, or headless on the
install command:

```shell
claude plugin install guardrails@<marketplace> --config hardcoded_path_check_enabled=false
```

Option scoping (user vs project settings, and the per-repository escape hatch)
per "How to set these" below.

One further option tunes the hooks' shared plumbing rather than a single guard:

- **`stdin_read_timeout`** (number, default `2`, minimum `1`). Idle bound in
  seconds on reading the hook payload from stdin. Any byte arriving resets it,
  so a large or slowly-delivered payload is never cut off while it is still
  coming; it fires only once the pipe has gone silent for that long, at which
  point a blocking guard fails **closed** (`exit 2` with a `BLOCKED:` reason)
  rather than letting an unscanned tool call through. On a shell whose `read -t`
  accepts fractional values the bound is read in four slices, so a stall is
  declared within a quarter of the configured interval of it. That quarter is
  the limit of the approximation, and it errs toward waiting rather than toward
  calling a live producer dead. Where fractional timeouts are unavailable (Bash
  3.2, the macOS system shell) the bound is read as one window instead, and a
  producer that sends bytes and then goes silent can take up to **two** intervals
  to be declared stalled. A value this shell's
  `read -t` will not accept, or `0`, which would make the read consume nothing,
  falls back to the default rather than disabling the guards. You should not
  need to change it.

## Consumer seams

The guards scope and tune themselves to **your** repository. They ship no
repo-specific policy of their own:

- **Project scoping.** `secret-pattern-detection` and `hardcoded-path-check`
  only police files under `$CLAUDE_PROJECT_DIR`; a write into a sibling repo is
  that repo's concern. With no active project (`CLAUDE_PROJECT_DIR` unset),
  or a project dir that is **not a git working tree** (a home-directory
  session, say; Claude Code sets the project dir for any directory), the two
  diverge by threat model: `hardcoded-path-check` skips entirely. Such a
  target (a `$HOME` dotfile, a machine-local `.claude/*.conf`) is
  machine-local, not a portable repo artifact, and outside a work tree the
  gitignore allowlist below could never exempt it, while secret scanning
  fails **closed** and scans anyway (secrets are dangerous anywhere).
- **Gitignore is the allowlist.** `hardcoded-path-check` skips any file
  `git check-ignore` matches against your `$CLAUDE_PROJECT_DIR`. Put
  machine-local files (`settings.local.json`, `.venv/`, …) in your
  `.gitignore` and they are exempt automatically. (Applies within an active
  project; with none, the hook already skips per the scoping rule above.)
- **Secret allowlist.** A generic built-in allowlist exempts dependency caches
  (`.venv/`, `node_modules/`), `.env.example` / `.sample` / `.template`
  placeholders, `tests/fixtures` / `tests/testdata` trees, `settings.local.json`,
  `CLAUDE.local.md`, and hook scripts.
- **CLI-flag tuning.** `cli-flag-verify` checks a default binary set
  (`claude gh dotnet docker kubectl terraform az aws`); override with the
  `cli_flag_verify_bins` option (`bin1,bin2,…`) and skip specific binaries
  with `cli_flag_verify_skip_bins`. `npm` is **excluded by default**, alongside
  `git` and `npx`: every npm config key is a flag on every subcommand
  (`npm <command> --key=value`), so per-subcommand `--help` is non-exhaustive by
  design and the authoritative list (`npm config ls -l`) prints `prefix = "…"`
  rather than `--prefix`. A generic `--help` parser cannot consume it, and
  verifying against one produces false "unknown flag" findings. Re-add it with
  `cli_flag_verify_bins` if your project wants it checked anyway.
- **Hook-manager prefixes.** `block-no-verify` reads its recognized
  hook-manager disable-env-var prefixes from `block_no_verify_hook_manager_prefixes`
  (comma list, default `lefthook, husky, pre_commit, simple_git_hooks`). Add a
  manager your project uses, or narrow the set. Values are reduced to identifier
  characters before use, so a consumer value can never inject regex metacharacters.
  The manager-agnostic `--no-verify` / `-n` and `core.hooksPath=` checks run
  regardless of this list.
- **Skill-availability gating.** `flag-commit-pr-skill-bypass` resolves
  `enabledPlugins` the way Claude Code merges it across scopes: user-global
  (`$CLAUDE_CONFIG_DIR/settings.json`, else `~/.claude/settings.json`) as the
  base, the project's `.claude/settings.json` overriding it, and
  `.claude/settings.local.json` overriding that. A local override counts only
  for a key the project already declares: CC ignores a local-only key per
  [anthropics/claude-code#27247](https://github.com/anthropics/claude-code/issues/27247).
  Each exact `source-control@…` key is resolved independently; if ANY resolves
  enabled the advisory fires. So a plugin enabled **only** at user-global (a
  common install) still triggers it. The project need not carry its own
  `settings.json`. Missing/uncertain state (no key enabled at any scope, no jq)
  fails quiet. It never advises toward a skill that is not enabled for the session.

## Telemetry (opt-in)

Every guard emits one structured [hook-telemetry](../../docs/conventions/hook-telemetry/README.md)
envelope per run to whatever `HOOK_TELEMETRY_SINK` names, carrying `status`
(`blocked` on a guard block, `ok` otherwise), `duration_ms`, and a privacy-safe
`data` payload (category **labels** only, never a secret value, matched path,
or full command). Unset `HOOK_TELEMETRY_SINK` → no-op; the guards behave exactly
as before.

## Requirements

- **bash 5.0+** and **jq**, the guards' runtime. Without **jq**, each guard
  fails **open** (disabled) and prints a one-line stderr notice, never a silent
  disable.
- On Windows, **Git Bash** (the hooks run via Git Bash's bash).
- `cli-flag-verify` runs `<bin> --help` for the binaries it scans; findings
  require those binaries on PATH (missing binaries are skipped, never flagged).

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install guardrails@<marketplace>
```

Then verify the runtime prerequisites and live guard surface with
`/guardrails:setup check`; `/guardrails:setup apply` resolves anything the
check reports with guidance. Opt-in personal git hooks:
`/guardrails:setup apply install-commit-msg` (commit-convention depth layer) and
`/guardrails:setup apply install-pre-commit-content` (secret / hardcoded-path
content invariants on every staged blob, write-path-independent).

## Configuration

<!-- ai-slop-ignore-start: generated options block; source is plugin.json + scripts/sync-plugin-options-docs.py -->
<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `secret_pattern_detection_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_SECRET_PATTERN_DETECTION_ENABLED` | Block writes containing high-confidence secret/credential patterns |
| `hardcoded_path_check_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_HARDCODED_PATH_CHECK_ENABLED` | Block writes containing hardcoded machine-specific paths |
| `block_no_verify_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BLOCK_NO_VERIFY_ENABLED` | Block git hook-bypass attempts (--no-verify, core.hooksPath=, hook-manager env-var disables for a configurable set — lefthook/husky/pre-commit/simple-git-hooks by default) |
| `block_dangerous_git_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ENABLED` | Block irreversible git operations (push --force, push --force-with-lease leasing against a value git resolves at push time — either no expected value, or an expectation that is not an object id of the repository's own hash width — reset --hard, clean -f, worktree-wide checkout/restore discards) |
| `block_hook_bypass_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BLOCK_HOOK_BYPASS_ENABLED` | Block Bash file-write workarounds that circumvent Write/Edit hook gates |
| `block_windows_drive_tmp_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BLOCK_WINDOWS_DRIVE_TMP_ENABLED` | Block writes whose target is a Windows drive-root temp path (/tmp, C:\tmp, \tmp, /c/tmp) that resolves to <drive>:\tmp instead of %TEMP% — both Bash/PowerShell commands and Write/Edit/MultiEdit/NotebookEdit file paths. One switch covers both lanes |
| `block_exported_msys_pathconv_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BLOCK_EXPORTED_MSYS_PATHCONV_ENABLED` | Block a leaking MSYS path-conversion suppressor on Windows: an EXPORTED MSYS_NO_PATHCONV / MSYS2_ARG_CONV_EXCL, or a prefix on a child shell (MSYS_NO_PATHCONV=1 bash -c ...). Either switches off conversion for later commands, letting an unconverted /d/... reach git as <current-drive>:\d\...; a prefix on a non-shell command word and a bare assignment are not matched |
| `block_noncanonical_commit_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BLOCK_NONCANONICAL_COMMIT_ENABLED` | Block `git commit -m` when the message actually contains a newline (multi-line `-m` mangles across shells — pipe it via `-F -` instead; single-line `-m` passes); --amend, -C/-c, --fixup/--squash, -F <path>, and an in-progress merge/rebase are exempt |
| `block_convention_gate_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BLOCK_CONVENTION_GATE_ENABLED` | Block a commit subject or `gh pr create --title` that violates the team-tracked convention pattern in .claude/source-control.md (no tracked pattern = no enforcement; same exemptions as block-noncanonical-commit) |
| `cli_flag_verify_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_CLI_FLAG_VERIFY_ENABLED` | Advise on hallucinated CLI flags written to files (never blocks) |
| `skill_reference_verify_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_SKILL_REFERENCE_VERIFY_ENABLED` | Advise when markdown cites a /plugin:skill reference this repo owns but cannot resolve (never blocks) |
| `stale_path_verify_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_STALE_PATH_VERIFY_ENABLED` | Advise when markdown cites a repo-relative path this repo's own history shows was removed and that is gone from the working tree (never blocks) |
| `workflow_resilience_check_enabled` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_WORKFLOW_RESILIENCE_CHECK_ENABLED` | Advise on un-throttled Workflow fan-out (never blocks). Default off since 0.20.0: a behavioral-class prose injector, config-disabled per the instruction-economy evidence gate (#2021) — set true to opt back in |
| `flag_commit_pr_skill_bypass_enabled` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_FLAG_COMMIT_PR_SKILL_BYPASS_ENABLED` | Advise when a direct gh pr create bypasses the source-control pull-request skill (never blocks). Default off since 0.20.0: a behavioral-class prose injector, config-disabled per the instruction-economy evidence gate (#2021) — set true to opt back in |
| `cli_flag_verify_bins` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_CLI_FLAG_VERIFY_BINS` | Comma-separated binaries cli-flag-verify scans; empty uses the built-in default set |
| `cli_flag_verify_skip_bins` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_CLI_FLAG_VERIFY_SKIP_BINS` | Comma-separated binaries cli-flag-verify must never scan |
| `block_dangerous_git_allow` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW` | Comma-separated forms block-dangerous-git permits: push-force, push-lease-unsafe, reset-hard, clean-force, checkout-dot, restore-dot, checkout-force, plus PowerShell fail-closed sink shapes ps-unparsable-dynamic-invocation, ps-unparsable-launcher, ps-unparsable-special-construct, ps-unparsable-herestring-unbalanced; empty blocks all |
| `block_noncanonical_commit_allow` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_BLOCK_NONCANONICAL_COMMIT_ALLOW` | Comma-separated form tokens to allow (currently: message-flag, which permits `-m` even when the message contains a newline) |
| `block_no_verify_hook_manager_prefixes` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_BLOCK_NO_VERIFY_HOOK_MANAGER_PREFIXES` | Comma-separated hook-manager env-var name prefixes block-no-verify treats as a bypass when set to 0/false (e.g. lefthook,husky); empty uses the built-in default set (lefthook, husky, pre_commit, simple_git_hooks) |
| `block_hook_bypass_scratch_roots` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_BLOCK_HOOK_BYPASS_SCRATCH_ROOTS` | Comma-separated ABSOLUTE directories block-hook-bypass exempts as scratch/temp write targets (e.g. /tmp/scratch,/d/jobtmp/session). This list is empty by default and ADDS TO the one root the guard already ships exempt — the host temp trees, which the harness scratchpad sits under — gated on CLAUDE_PROJECT_DIR naming a project root outside the temp tree. Set this to name a scratch root of your own; the kill switch, not this option, is the whole-guard lever. The memory tier (`<memory_dir>/`, default `.work/`) is deliberately NOT a shipped default: secret-pattern-detection scans a Write there, so exempting Bash redirects to it would let a secret reach disk unscanned. Matching is on the effective stdout target after lexical normalization, at a path-component boundary — a sibling merely sharing the name prefix, a `..` escape out of a root, and a discard-then-real-file redirect all still block. A relative target is resolved against the tool call's own cwd and refused when the command carries a cd/pushd/popd. A quoted or escaped OPERAND is never exempt: the operand is marked so it survives the quote strip and the segment split as one word, and an operand carrying whitespace, `;`, `\|`, `&`, `(`, `)`, a newline or a backslash escape exempts nothing. Quotes elsewhere in the command no longer matter. Symlinks are not followed for a CONFIGURED root (an operator naming a root accepts its contents); the shipped temp default resolves them before exempting |
| `stdin_read_timeout` | number<br>*min 1* | `2` | `CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT` | Idle bound on reading the hook payload from stdin — how long a silent pipe is tolerated before a blocking guard fails closed |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively** — Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure guardrails@<marketplace>`.
2. **Headless** — repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install guardrails@<marketplace> -s <scope> --config secret_pattern_detection_enabled=<value>
   ```

   The same command reconfigures a plugin that is **already installed**: it prints
   `already installed` and still writes the value. The short-circuit message is
   about the install, not the config write. Do **not** `claude plugin uninstall` to
   reconfigure: uninstalling drops this plugin's whole stored `pluginConfigs` entry,
   resetting every option in the table above to its default. `-s` defaults to `user`,
   so pass the scope `claude plugin list` reports for this plugin. The verified-version
   record lives in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md).

   The value is stored immediately; the session you are in does not change. Hooks are
   handed their `CLAUDE_PLUGIN_OPTION_*` when the session starts, so start a fresh
   Claude Code session before expecting new behavior. A check run in the old session
   still reports the old value, and that is not a failed write.

3. **By hand, in settings** — add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "guardrails@<marketplace>": {
         "options": {
           "secret_pattern_detection_enabled": <value>
         }
       }
     }
   }
   ```

   Plugin option values are read from **user**, `--settings`, and managed settings
   only — **not** from a project's `.claude/settings.json`. To vary behavior per
   repository, enable or disable the plugin in that project's `enabledPlugins`
   instead of setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration) — the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins-reference#plugin-install) — the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills) — `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect) — user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins) — enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->
<!-- ai-slop-ignore-end -->

## License

MIT (SPDX-License-Identifier: MIT).
