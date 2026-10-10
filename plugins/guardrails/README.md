# guardrails

A Claude Code plugin bundling fifteen **safety guards** that catch risky agent
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
process, and sources each guard in turn inside that one bash process. Since **0.41.3**
those rows are exec form: `"command": "node"` with `hooks/exec-bash.mjs` and the
dispatcher script in `args`. Each fire starts two processes: node, which finds bash
(the candidate order is in the header of `hooks/exec-bash.mjs`; on Windows it is Git Bash,
never the WSL relay) and spawns it, then that bash, which sources every guard in one
process. `workflow-resilience-check.sh` is
the same exec form, with `--require-true WORKFLOW_RESILIENCE_CHECK_ENABLED` so the
default-off checker exits in node before bash starts. The table below
still names every guard, and every guard still ships as its own script with its own
contract test, kill switch, and telemetry envelope, deciding exactly as it did as a
standalone hook. `hooks/hooks.json` lists each guard by file name as an argument of the
dispatcher for its event, so the registration stays readable per guard. What the
dispatcher owns: the spawn shape (one bash process per Bash/PowerShell call where there
were eight, one per Write/Edit PreToolUse where there were three, one per Write/Edit
PostToolUse where there were three, each started by the node entry), the exit code (2 if any guard blocks, and every
guard still runs so a command that trips two guards shows both reasons; that
is deliberate, not leftover work, so a dual-blocked PowerShell sink prints both
denials instead of hiding one ([#4236](https://github.com/melodic-software/claude-code-plugins/issues/4236))), and the merge
of several guards' `additionalContext` into the one JSON document a hook process may
emit. On the Bash/PowerShell row it also refuses (exit 2) a command holding more than
256 command or process substitutions (`$(`, `<(`, `>(`, a backtick pair) before any guard
runs, because the guards' combined cost grows with that count and a row cancelled at its
60-second `timeout` blocks nothing
([#4684](https://github.com/melodic-software/claude-code-plugins/issues/4684)).
On the Bash tool, text inside a single-quoted span does not count, whichever spelling it
holds, because bash substitutes nothing there. Nor does the body of a heredoc whose
delimiter is quoted (`<<'EOF'`, `<<"EOF"`, `<<\EOF`): bash expands nothing there, and
`block-root-delete-target` still reads such a body as commands, at about 1.1 ms per
spelling. For a body that gives it nothing to judge (`$(: rm)`) its 25-second deadline never
starts, so the 16384-character command ceiling bounds the cost: 2.6 to 3.7 s measured.
Unquoted, double-quoted and unquoted-heredoc-body substitutions still
count. A command that names a shell, `eval`, `su`, `env`, `source`,
`. file` or `alias`, or that has quoting the scan does not model, counts whole. PowerShell commands
count as text, quotes included.
It also tokenizes the event's command once and hands every guard that parses it
the same segments. One exception to "every guard still runs": on the Bash/PowerShell
row, a command longer than `MAX_COMMAND_LEN` (16384 characters, passed to the dispatcher
as `--max-command-len`) ends the chain at the first guard that blocks it. The five
guards that carry that ceiling refuse such a command unread, and the row now answers a
~70 KB command in about 64 ms instead of running past its 60-second `timeout`, where
Claude Code would let the call through unchecked (#4528). Each guard keeps its kill
switch; with one disabled, the next guard carrying the ceiling blocks.
The [hook budget accounting](#hook-budget-accounting) carries the measurement.
`workflow-resilience-check` is not always-on and is registered on its own.

An installed mod can stop this plugin's `PreToolUse` hooks from running: they run after the last
mod calls `next`, so a mod that answers a `tool.call` without calling it skips them
([where settings hooks run in the order](https://code.claude.com/docs/en/plugins/mods/events#where-settings-hooks-run-in-the-order)).
A mod can also approve a call they blocked, because its `tool.check` hook runs after them
([approve or refuse a tool call before the user is asked](https://code.claude.com/docs/en/plugins/mods/events#approve-or-refuse-a-tool-call-before-the-user-is-asked)).

| Guard | Event / matcher | Behavior | What it catches |
|-------|-----------------|----------|-----------------|
| **secret-pattern-detection** | PreToolUse · Write \| Edit \| NotebookEdit **and** `mcp__github__push_files` \| `mcp__github__create_or_update_file` (also `mcp__plugin_<plugin>_github__<tool>`, see Scope notes) | **Blocks** (exit 2) | High-confidence secret/credential patterns (AWS/GitHub/GitLab/Slack/Stripe/OpenAI keys, PEM private keys) in new file content. Since **0.32.0** also in content bound for a GitHub repository through an MCP write, where there is no local file to fix afterwards and no pre-commit hook on the path. |
| **hardcoded-path-check** | PreToolUse · Write \| Edit \| NotebookEdit **and** `mcp__github__push_files` \| `mcp__github__create_or_update_file` (also `mcp__plugin_<plugin>_github__<tool>`, see Scope notes) | **Blocks** (exit 2) | Hardcoded machine-specific paths: Windows drive-letter homes, macOS/Linux user homes, machine-specific repo checkout roots. Since **0.32.0** also on the GitHub MCP write lane, which catches the session's own checkout path leaking into pushed content. |
| **block-no-verify** | PreToolUse · Bash \| PowerShell | **Blocks** (exit 2) | Git hook-bypass attempts on `git commit` / `git push`: `--no-verify` / `-n`, `core.hooksPath=` assignment, and hook-manager disable env vars, a configurable prefix set defaulting to `lefthook`, `husky`, `pre_commit`, `simple_git_hooks` (e.g. `LEFTHOOK=0`, `HUSKY=0`, `PRE_COMMIT_*=false`), tunable via `block_no_verify_hook_manager_prefixes`, including inside compound `cd … && …` commands. |
| **block-dangerous-git** | PreToolUse · Bash \| PowerShell | **Blocks** (exit 2) | Irreversible git operations: `push --force`/`-f` plus the equivalent leading-`+` refspec and `--mirror` forms, and the unsafe `--force-with-lease` spellings, in the two kinds git itself treats differently. **No expected value** (bare `--force-with-lease` or `=<refname>`) leases against the remote-tracking ref, which git documents as "trivially defeated" by a background fetch, blocked unless `--force-if-includes` is present, which git documents as the mitigation for exactly this form. **A movable `=<refname>:<expect>`**, such as `origin/main`, `HEAD`, a tag, an *abbreviated* object id, or hex of the wrong width for this repository's hash format, all of which git resolves at push time, and gitrevisions resolves a short hex word as a ref before trying it as an object-id prefix, is blocked unconditionally, because git declares `--force-if-includes` a no-op alongside an explicit `:<expect>`. A lease passes only when `<expect>` is immutable: a **literal** object id of the pushed repository's own hash width (detection never evaluates substitutions, so resolve it with `git rev-parse` as a separate step and pass the result) (40 hex under SHA-1, 64 under SHA-256, read from `git rev-parse --show-object-format` with the command's own `-C`/`--git-dir`/`--work-tree`/`--namespace` replayed onto it; undeterminable fails closed) or the empty string asserting the ref must not exist. The other width is a ref name there, not an object id. git ignores a ref whose name is full-width hex for its own format, but resolves one of the other width like any name. git scopes a pin to its own ref, so a bare fallback alongside a pinned entry still governs every other ref being updated; where the same ref carries several lease entries, git consults the first, and so does this guard. A trailing `--no-force-with-lease` cancels every previous lease, and a push dry-run disarms the check. Also blocked: `reset --hard`, `clean` with a force flag (any dry-run flag disarms), worktree-wide `checkout`/`restore` pathspecs (`.`, `:/`, `:(top…)`; path-scoped forms and `restore --staged .` pass), and forced `checkout -f` / `switch --discard-changes`. Accepted unique-prefix abbreviations of the blocked long options match too. `branch -D` is deliberately not blocked (reflog-recoverable; sanctioned skill flows issue it). Per-repo/per-user allow-list via the `block_dangerous_git_allow` userConfig option (comma list, any subset of `push-force,push-lease-unsafe,reset-hard,clean-force,checkout-dot,restore-dot,checkout-force`). |
| **block-hook-bypass** | PreToolUse · Bash \| PowerShell | **Blocks** (exit 2) | Bash file-write workarounds that circumvent the Write/Edit hook gates: `cat > file`, `echo … > file`, inline python code with file-write indicators (`python`/`python3`/`py`/`pypy`, with `-c` or reading the program from stdin as `python3 - <<PY`), and a same-command staged write whose effective redirect target is reused as an `mv`/`cp` source toward a non-scratch destination. Executable-token detection ignores quoted prose/commit text that merely mentions the pattern. |
| **check-bash-file-changes** | PreToolUse, PostToolUse and PostToolUseFailure · Bash \| PowerShell | **Reports** (the command already ran) | A repository file a shell command changed that a Write or Edit of the same content would be blocked for: the guards of the PreToolUse Write \| Edit row (secret-pattern-detection, hardcoded-path-check, block-windows-drive-tmp) run on each changed file, so `node x.js` or `python3 x.py` writing a file meets the same checks as an Edit of it ([#6674](https://github.com/melodic-software/claude-code-plugins/issues/6674)). The PreToolUse fire records `git status`, the HEAD commit, and each dirty path's size and mtime for the repository holding the call's cwd; the post fire runs the guards on every path new to `git status` or whose size or mtime moved, and on the paths commits made by the command added or modified (judged from the HEAD reflog, so a checkout, pull or merge adds none), a new file as a Write of its whole content and a tracked file as an Edit of the lines it adds against the pre-command HEAD, staged or not. Findings reach Claude as the PostToolUse block reason, or as `additionalContext` when the command failed. Fails open and starts nothing outside a git repository. Snapshots live under the plugin data directory only; without one it does nothing. Git runs with fsmonitor and textconv off, so a repository config the command wrote starts no program outside the sandbox. A change it did not examine is reported as `additionalContext`, or beside a finding in the block reason, and never blocks on its own: no snapshot recorded before the command, a `git status` that failed or listed more than 10000 paths, a new symbolic link (never followed), files past the first 20 changed or past the time budget, and a background command, whose later writes are not checked. Not covered and not reported: a file outside the cwd's repository, a gitignored file, a change inside a submodule, a file that was already dirty with its size and mtime unchanged, a file over 1 MiB or binary, and a file the command wrote and then deleted. |
| **block-windows-drive-tmp** | PreToolUse · Bash \| PowerShell **and** Write \| Edit \| NotebookEdit | **Blocks** (exit 2) | Windows-only: write targets that are a drive-root temp path: POSIX `/tmp`, MSYS `/c/tmp`, `C:\tmp`, or drive-root `\tmp`, which resolve to `<drive>:\tmp` instead of `%TEMP%` and accumulate at the volume root. On a stock Git for Windows install the Bash-tool POSIX `/tmp` is a `usertemp` mount of `%TEMP%` itself, so that spelling is not blocked there; `/c/tmp`, `C:\tmp`, `\tmp`, PowerShell `/tmp`, and the file-path lane still are. On the **command lane** redirects and write utilities (`mkdir`/`mktemp`/`tee`/`cp`/`curl -o`/`--output-dir` (bare or bundled, as in `-sSLo`)/`wget -O`/`Set-Content`/`Out-File`/…) are blocked; on the **file-path lane** (since **0.30.0**) the tool's own `file_path` / `notebook_path` is matched directly, because on a Write the path *is* the write target. Both lanes call one matcher, so the same spellings block and the same ones pass. Does not fire on non-Windows hosts; leaves `%TEMP%` / `$TEMP` / `$TMPDIR` / `$env:TEMP` / `/var/tmp`, relative `./tmp`, `foo/tmp`, `/tmpdir`, `C:/tmp2` and UNC `\\server\tmp` alone. Covers the `tmp` spellings only: `C:\Temp` and other `Temp` directories are not matched. Inline python `open (` and `getattr(__builtins__,'open')(` count as writes, except a provable read: a bare one-argument `open(` (optional read-only mode `r`/`b`/`t`, optional literal `encoding=`/`errors=`/`newline=`) followed by `.read(`/`.readline(`/`.readlines(` or wrapped whole in `json.load(`, e.g. `json.load(open('/tmp/x.json'))`. That exemption is judged over the whole unsplit command, never per segment, and applies only when that command is one plain python run (`python`, `python3` or `py` with plain flags) whose code is its `-c` string or a heredoc on stdin, with no pipe, `;`, `&&`, redirect, argument, wrapper, second command or later line, so a pipeline cannot lift the path out of the text and write it (`echo "open('/c/tmp/x').read()" \| cut -d "'" -f2 \| xargs tee`): every `open` in the command must be such a read and no drive-root temp path may remain outside those calls, so a decoy read beside a write (`os.system`, `shutil.copy`, a second `open(..., 'w')`, a heredoc body) still blocks. Fail-closed: the method form (`Path(...).open()`), a variable or non-read mode, an argument that is not a plain path (a leading pipe that Ruby's `open` runs as a subprocess, `%x[...]`, `#{...}`), an argv operand, any `\`, `$` or backtick in the command, and indirection (`exec`, `eval`, `getattr`, `subprocess`, `os.popen`, ...) keep the block. Quoted `open(` / `write_text(` text counts as data only when the whole command, with every quoted string replaced by one placeholder word, is exactly one of `gh issue` or `gh pr` with `create`, `comment` or `edit`, `git commit`, `git tag`, `echo` or `printf`, with plain flag words, on the Bash tool and with no `\`, `$`, backtick, operator, newline, glob or redirect, so `gh issue create --body "...open('/tmp/x','w')..."` passes while any other command, including an interpreter this guard does not know, blocks. The read exemption also keeps the block when the token `tmp` remains outside the read calls. A deterrent over one command string, not a sandbox: concatenated or computed paths pass. |
| **block-exported-msys-pathconv** | PreToolUse · Bash \| PowerShell | **Blocks** (exit 2) | Windows-only: an **exported** `MSYS_NO_PATHCONV` / `MSYS2_ARG_CONV_EXCL` (also the `declare -x` / `typeset -x` spellings), which switches off MSYS argv rewriting for every *later* command in the same command string. A later path argument then reaches a Windows-native program unconverted and git resolves its leading `/` against the current drive, so `git worktree add /d/worktrees/x` creates `<current-drive>:\d\worktrees\x` (#2870). Deliberately keys on the environment, not on a path shape: the incident command's path argument was identical to one that had already worked. A prefix whose command word is a **shell** (`MSYS_NO_PATHCONV=1 bash -c '…'`, `env … sh -c '…'`) blocks too: the prefix scopes to one *process*, and when that process is an interpreter, one process is every command inside it. A prefix on a **non-shell** command word (`MSYS_NO_PATHCONV=1 git show …`) and a bare assignment are not matched. The first scopes to exactly that command, and the second has no effect at all because the MSYS runtime reads the environment. Does not fire on non-Windows hosts. |
| **block-root-delete-target** | PreToolUse · Bash \| PowerShell | **Blocks** (exit 2) | A recursive `rm` whose target normalizes to a filesystem root. The command is parsed the way the shell builds argv, through launchers (`sudo`, `env`, `timeout`, the util-linux family including `setpriv` and `prlimit`, `systemd-run`), child shells (`bash -c`, `su -c`, `sg`), `eval` and command substitutions, and a segment is judged when its command word is `rm` with a recursive flag. Roots: `/` and `/*`, the MSYS-translated bare backslash in both its quoted (`rm -rf "\\"`, the shape behind the whole-volume loss in anthropics/claude-code#92593, which no permission pattern keyed on `rm -rf /*` matches) and **dangling** (`rm -rf \`) spellings, `~`, a literal `$HOME` / `${HOME}`, a drive root (`C:\`, `c:/`, `C:`), an MSYS, WSL or cygdrive drive root (`/c`, `/mnt/c`, `/cygdrive/c`), and a UNC share root (`//server/share`). `--no-preserve-root` is refused whatever it targets. Also refused: an **empty operand** (`rm -rf ""`), a **bare variable operand** made of expansions alone (`$X`, `"$X/"`, `"$X"/*`, `$X$Y`, any `${...}` form but `"${X:?}/"`), and, when the payload carries an absolute `cwd`, a target **outside the session's allowed roots**: not under the git toplevel of the payload cwd, and not strictly under a temp root, the session scratchpad or a root you list in `block_root_delete_target_allowed_roots` (`rm -rf ../../..`, `rm -rf ~/Documents/x`, `cd / && rm -rf *`, `rm -rf {/c,x}`, `rm -rf /c/Users/*/.claude`, a `link/` that points outside). Not host-gated. The guard's header in `hooks/block-root-delete-target.sh` lists how braces, globs, directory changes and symlinks are judged, the bounds past which it refuses, the known false positives, and the declared gaps. On the PowerShell tool the same classes are refused for `Remove-Item -Recurse` (aliases `ri`/`rm`/`rd`/`rmdir`, prefixes `-r`/`-rec`) and for `cmd /c rd /s` / `rmdir /s`, without loading the shared PowerShell classifier ([#4516](https://github.com/melodic-software/claude-code-plugins/issues/4516)). Each statement is judged, including one after a newline and one inside a `{ }` scriptblock, a `( )` grouping or `$( )`, and a `Remove-Item` target that is a grouping is refused. `$env:NAME` and `${env:NAME}` are judged as the Bash lane judges `$NAME`: refused bare or followed only by `\` or `\*`, allowed with a named subpath (`$env:TEMP\build`). Not covered: a delete wrapped in `Start-Process` or `Invoke-Expression`, nested PowerShell, a command that is not the first word of its statement (`$r = Remove-Item -Recurse C:\`), a comma list of targets, and a here-string. |
| **block-credential-read** | PreToolUse · Bash \| PowerShell | **Blocks** (exit 2) | A command whose output is a credential: `git credential fill`, credential-helper `get`, `gh auth token`, `echo`/`printenv` of a token-shaped variable, `jq env` (every variable), `cat` of `.git-credentials`, `.netrc`, `.env`, `.credentials.json` or `.docker/config.json`, and `jq` of the last two. Presence checks such as `gh auth status` and `test -n "$GH_TOKEN"` pass. The guard header in `hooks/block-credential-read.sh` lists the known gaps and false positives. Escape: `block_credential_read_enabled` (off switch) or `block_credential_read_allow` (comma list of `credential-fill`, `gh-auth-token`, `env-echo`, `credential-file-read`). |
| **cli-flag-verify** | PostToolUse · Write \| Edit, dispatcher `if`-gated to `.md`, `.sh`, `.bash`, `.ps1`, `.psm1` | **Advisory** (exit 0) | Hallucinated CLI flags: a `--flag` written as a command that does not exist in the binary's actual `--help` output. Surfaces via `additionalContext`, never blocks. |
| **workflow-resilience-check** | PreToolUse · Workflow | **Advisory** (exit 0) | Un-throttled Workflow fan-out: a script calling `parallel()` / `pipeline()` with no wave-cap throttle (`inWaves` / `inWavesPipeline`) and no retry wrapper (`agentRetry`), which risks a burst 529 under wide Opus fan-out. Surfaces a one-line advisory via `additionalContext` that points at the workflow-authoring skill, never blocks. **Opt-in. Default off since 0.20.0** (behavioral-class injector config-disabled per #2021; set `workflow_resilience_check_enabled=true` to enable). |
| **block-noncanonical-commit** | PreToolUse · Bash \| PowerShell | **Blocks** (exit 2) | `git commit -m` whose message actually contains a newline. A multi-line `-m` flattens newlines unpredictably across shells; pipe it via `-F -` / `--file -` instead (narrowed in 0.20.0 per #2021: single-line `-m`, bare `git commit`, and repeated single-line `-m` paragraphs all pass). On the PowerShell tool a here-string `-m` value blocks too. Its content is uninspectable and multi-line by construction of the form. Exempt: `--amend`, `-C`/`-c`/`--reuse-message`/`--reedit-message`, `--fixup`/`--squash`, `-F <path>`, and any commit taken while a merge/rebase/cherry-pick/revert is in progress. Resolves `bash -lc` wrappers and git aliases (inline `-c` and persisted config alike). |
| **block-convention-violation** | PreToolUse · Bash \| PowerShell | **Blocks** (exit 2) | A commit subject or `gh pr create --title` that violates the team-tracked convention pattern declared in `.claude/source-control.md`. No tracked pattern means no enforcement. Same exemptions as `block-noncanonical-commit`. |
| **flag-commit-pr-skill-bypass** | PreToolUse · Bash \| PowerShell | **Advisory** (exit 0) | Any `gh pr create`, bypassing this marketplace's own `/source-control:pull-request` skill. Only fires when the consuming project's own `.claude/settings.json` enables the `source-control` plugin, and is silent otherwise. Surfaces via `additionalContext` once per session and agent, never blocks. **Opt-in. Default off since 0.20.0** (behavioral-class injector config-disabled per #2021; set `flag_commit_pr_skill_bypass_enabled=true` to enable). |
| **skill-reference-verify** | PostToolUse · Write \| Edit, dispatcher `if`-gated as above, the guard itself scans `.md` only | **Advisory** (exit 0) | A `` `/plugin:skill` `` reference in markdown that does not resolve. Only fires inside a marketplace repo, and only for a plugin that repo's own manifests own. A reference to another marketplace is left alone. Resolves through manifest and frontmatter `name`, so a renamed directory still matches. Surfaces via `additionalContext`, never blocks. |
| **stale-path-verify** | PostToolUse · Write \| Edit, dispatcher `if`-gated as above, the guard itself scans `.md` only | **Advisory** (exit 0) | A repo-relative path cited in a markdown inline code span that this repo's own history shows was **deleted** and that is gone from the working tree. The gate is provenance, not absence: the exact path must appear in `git log HEAD --no-renames --diff-filter=D --name-only`, so a path belonging to a consuming project's tree, an example, or a plan is never adjudicated. Names the surviving file when exactly one tracked path now carries that basename. Link destinations are out of scope. Surfaces via `additionalContext`, never blocks. |

The ten blocking guards feed their stderr message back to Claude as
actionable fix guidance. The five advisory guards surface their findings the same
way but always allow the operation. check-bash-file-changes passes on the blocking
guards' own message after the command has run.

### Enforceability tiers

Thirteen guards are **deterministic**. Their oracle is a mechanical test with no
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
- **PowerShell env assignment and same-command alias.** On the PowerShell
  lane, `$env:LEFTHOOK=0`, `Set-Item env:HUSKY 0` and `si env:HUSKY 0` block when
  the same command also runs `git commit` or `git push`, over the same prefix
  set, with `-Path`/`-Value` in any order. In either lane,
  `git config alias.NAME '<value with --no-verify / -n>'` followed by
  `git NAME`, or `git -c alias.NAME='<value>' NAME`, in the same command
  blocks. A `--config-env` alias blocks. Known residuals: an alias
  defined by an earlier command or in a config file is not seen, so a later
  `git NAME` commits without the flag being judged; and a PowerShell comment
  holding an assignment (`# $env:LEFTHOOK=0`) beside a commit still blocks,
  because comments are not stripped.
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
- **`wsl` / `wsl.exe` is read like `bash -c`** (since **0.38.11**). It runs its
  command line inside a Linux distribution, so every guard that re-parses a
  `sh -c` operand (`block-no-verify`, `block-dangerous-git`,
  `block-hook-bypass`, `block-noncanonical-commit`, `block-convention-violation`,
  `block-root-delete-target`) re-parses that command line too: `wsl git reset
  --hard`, `wsl.exe -e git reset --hard` and `wsl -d Ubuntu -- rm -rf /` block.
  `wsl`'s run options (`-d`, `-u`, `--cd`, `--shell-type`, `--`) and a leading
  `~` are stepped over, as is an option it does not know. Without `-e` /
  `--exec` wsl hands its raw Windows command line to `$SHELL -c`, so the words
  are rebuilt the way Git Bash builds that line: a word with whitespace is
  double-quoted, so `wsl bash -c 'git reset --hard'` blocks while
  `wsl 'git status && git clean -fd'` is one command word to the distro shell.
  With `-e` each word stays one argv word. On the
  PowerShell tool `wsl` is a launcher, so it reaches the fail-closed sink with
  `Start-Process`, `pwsh` and `cmd`. Not covered: `block-windows-drive-tmp` and
  `block-exported-msys-pathconv` do not re-parse a `-c` operand at all, and
  `block-root-delete-target` judges a relative target from the payload `cwd`,
  not from `wsl --cd`.
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
  read is not dependably the text that would run: two behaviors were measured
  and they disagree. bash **discards** a NUL while parsing a command it reads,
  and Node's `child_process` **refuses** a NUL-bearing string outright.
  Which of them, if either, a hook payload reaches has not been traced. Refusing
  is the one verdict correct under all of them, and needs no such trace. A NUL is
  treated as malformed input rather than as an exotic-but-valid command. Under
  the dispatcher every guard that refuses it shares one deny reason, so the
  refusal is printed once per call; so are the jq-missing denial, a shared git
  alias refusal and the PowerShell unparsable-command message.
- **Read-only git inside PowerShell grouping passes; anything else in it is
  refused.** A PowerShell command carrying a construct the git guards cannot
  tokenize (`{}` / `()`, a backtick, `--%`, a subexpression) goes to a
  fail-closed sink. `block-dangerous-git` lets it through when every git
  invocation is a built-in interrogator (`status`, `log`, `show`, `diff`,
  `rev-parse`, `ls-files`, `remote` alone or `remote -v`, `remote show`,
  `stash list`, and similar), optionally behind `-C <path>`, so
  `foreach ($d in 'a','b') { git -C $d status; git -C $d log --oneline -3 }`
  runs. A `-c` override, `--exec-path`, a computed or obscured subcommand, an
  alias, `fetch`, `grep` or any mutating verb keeps the whole command blocked,
  as does an environment write the guard cannot prove has a plain literal
  target: `Set-Item`, `New-Item` or `Set-Content` with a path that is computed,
  held in a variable, splatted or piped in, an `Env:` provider path, a
  `$env:NAME` assignment, a static .NET call or any method call
  (`SetEnvironmentVariable`, `InvokeMember`, `.Invoke(`), `ForEach-Object
  -MemberName`, or a function, filter or alias definition. Dynamic invocation,
  launchers and here-string shapes block as before. The scan reads syntax, so a
  name split in pieces is refused too; it does not read code in a file. A
  blocked loop runs once unrolled into flat statements (`git -C <path> status;
  git -C <path> log --oneline -3`)
  ([#4236](https://github.com/melodic-software/claude-code-plugins/issues/4236),
  [#4235](https://github.com/melodic-software/claude-code-plugins/issues/4235)).
- **Some PowerShell here-string shapes are refused with no allow token.** A
  confirmed here-string opener whose line prefix holds a quote, backslash or
  backtick (`Set-Content -Path "f.txt" -Value @'`, `Set-Content C:\tmp\f.txt @'`),
  a `<#` block comment earlier in the command, an orphan closer (`"@` or `'@` at
  column zero with no confirmed opener, including after a trailing-space opener),
  and any bare CR (including a trailing one) are each refused in all five blocking
  guards, and no allow token clears them. Rewrite with the opener alone on its own
  line and LF or CRLF line endings.
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
  `build.sh` performs. The inline operand of a child shell is in that string,
  so since **0.38.9** it is re-parsed and judged like the top level, nested
  shells included: `bash -c 'echo x > f'` and `sh -c 'cat > f <<EOF …'` block.
  `block-windows-drive-tmp` does not re-parse a `-c` operand, so
  `bash -c 'echo x > /tmp/f'` still reaches a drive-root temp path on Windows.
  It is also producer-scoped by design, so a redirect whose
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
  This entry is where that scope is stated. Since **0.38.0** the block message
  no longer prints it, so a blocked agent is not handed the list of unchecked
  write forms; the operator notice (once per session) points here instead.
- **`block-hook-bypass` block message and operator levers.** stderr is what the
  blocked agent reads, so it carries only what the agent can act on: the
  verdict, the Write/Edit remedy, and a remedy for when Write or Edit is refused
  too ("stop and tell the user"). On the `cat`, `echo`/`printf` and staged-move
  lanes it also says why the target was not scratch-exempt and lists the roots
  that exempt an unquoted literal target in this session, with no configuration
  needed for the temp tree when the project root is outside it, and that the
  user can add a root to `block_hook_bypass_scratch_roots`. It says a quoted
  or variable-carried target is never exempt. The python lane never consults a
  scratch root, and the PowerShell lane consults one only for a single literal
  destination, so their message names none. The operator's levers, narrowest
  first, are `block_hook_bypass_scratch_roots` (Bash redirect targets and a
  PowerShell command's single literal write destination), a session-scoped disable via `claude --settings`, and the
  user-global `block_hook_bypass_enabled` switch, which persists across every
  repository where guardrails is enabled. They arrive once per session as a
  `systemMessage`, which Claude Code reads on exit 2 as on exit 0
  (<https://code.claude.com/docs/en/hooks#exit-code-output>).
- **`block-hook-bypass` reads a PowerShell `& $var` call with two positionals
  as a file write.** A call through a variable (`& $sh x.sh record dir`,
  `& $py tool.py run x`) whose leading operands hold two or more positionals,
  at least one a bare word, has the shape of `Set-Content <path> <value>`,
  because the guard cannot tell what `$sh` names. It blocks. Rewrite it as
  `& 'C:/literal/path.exe' script args`, or put a flag first (`& $sh -File
  x.sh record dir`). An alias or function named like the program is not seen
  ([#4236](https://github.com/melodic-software/claude-code-plugins/issues/4236);
  the binding-to-literal relief is #4234).
- **Every hook says so when it could not run.** A hook has three outcomes,
  not two: allow (exit 0), block (exit 2), and could-not-run. Every registered
  hook and the dispatcher install the shared abort boundary
  (`hooks/abort-boundary.sh`, #3528) right after their first line. It passes
  the statuses the hook chooses through untouched and turns any other exit (an
  unbound variable under `set -u`, a helper that stopped existing, a
  `hook-utils.sh` that failed to load) into a one-line "guard did not run"
  notice naming the hook and the status, on stderr and as a `systemMessage`
  for the user (the model cannot fix a hook), then exits with the posture
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
  freeze the session, with the user notice so the allow is not silent.
  Stdin timeout and a NUL payload still fail closed. The 60s `hooks.json`
  `timeout` on this handler is a harness-level fail-open the plugin does not
  override: we treat a guard killed at that bound as letting the tool call
  proceed. Pointer: <https://code.claude.com/docs/en/hooks#timeouts>. As of:
  2026-10-01. Recheck trigger: that section changes what a timed-out
  `PreToolUse` command hook does to the tool call. What the
  plugin does instead is keep the row far from that bound: the command
  tokenizer is linear in the command's length, one parse serves every guard,
  and a command over `MAX_COMMAND_LEN` is refused by the first guard that
  carries the ceiling before anything tokenizes it (#4528).
- **`block-hook-bypass` option parse is strict.** Only the exact strings `true`
  and `false` are accepted (`unset` defaults to enabled). Any other value keeps
  the guard enabled and tells the user once per session. A typo must not silently disable
  a blocking safety control.
- **`block-hook-bypass` does not see MCP-provided shell or file-write tools.**
  The matcher is `Bash|PowerShell`. A write issued through an MCP tool is an
  accepted residual, same class as the unmonitored Bash forms above. The two
  CONTENT guards are the exception since **0.32.0**. See the next note.
- **The content guards cover the GitHub MCP write lane; the scope is exactly two
  tools.** `secret-pattern-detection` and `hardcoded-path-check` inspect
  `mcp__github__push_files` (every entry of its `files` array, not just the
  first) and `mcp__github__create_or_update_file`, and, since **0.37.1**, the
  same two tools from a plugin-bundled GitHub server, matched as
  `mcp__plugin_<plugin>_github__<tool>`. Pointer:
  <https://code.claude.com/docs/en/hooks#match-mcp-tools>. As of: 2026-09-27.
  Recheck trigger: that section changes how a plugin-bundled server's tools are
  named. This closes a real hole: a
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
  so applying it would skip every MCP write, a silent hole rather than a scope), the
  git-working-tree requirement, and `git check-ignore` (which answers what THIS
  checkout ignores, not the destination repo). The path ALLOWLIST is the same
  list, asked of the repo-relative path: an `.env.example` or a test fixture
  tree is the same false positive whichever route writes it.
  `hardcoded-path-check` still resolves its scan root, which is the most
  valuable half of the lane: it catches this machine's own checkout path
  appearing verbatim in content being pushed.
- **`block-hook-bypass` ships two scratch roots exempt, and takes more by
  configuration.** Since **0.32.0** the guard exempts the host temp trees, which
  the harness's own per-session scratchpad sits under, and since **0.33.0** the
  plugin data directory (`<config dir>/plugins/data`, the config dir being
  `CLAUDE_CONFIG_DIR` or `~/.claude`), where a plugin persists its reports. Each
  is gated on `CLAUDE_PROJECT_DIR` naming a project root that does **not** contain
  it: with no project root neither fires; when the project root is itself
  temp-rooted a temp file is project content, and when it is `~` or an ancestor
  of the config dir the plugin data directory is, so the default stands down.
  Neither removes protection: the Write|Edit content gates decline a file outside
  the project root, so a redirect there bypasses nothing. Neither is spelled
  as a static default, because neither has a fixed spelling: the scratchpad path
  carries a session id, so it resolves at run time.

  **Exempting it gives up little protection**, which is the only reason a default
  is defensible here: guardrails' own `Write|Edit` gates decline most temp-tree
  files reached from a known project root outside the temp tree.
  `secret-pattern-detection` declines them by its own check, which resolves the
  target's physical path and applies a gate never wider than this default;
  `hardcoded-path-check` and `block-windows-drive-tmp` decline them through their
  project scope. `Write` still scans some temp targets the Bash redirect exempts
  (a hard-linked file, a `/`-spelled target on Windows, a temp tree spelled with
  capitals on POSIX); the 0.36.5 changelog entry lists them. Before 0.32.0 these
  redirects blocked anyway, which cost false positives with no true positive.

  **On the PowerShell tool the roots exempt one literal write.** A command
  that is exactly one write, `Out-File`, `Set-Content`, `Add-Content`,
  `Tee-Object`, `Export-Csv` / `epcsv`, `Export-Clixml` or a `>`/`>>`
  redirect, to one absolute destination (a drive path such as
  `C:\Users\<user>\.claude\plugins\data\<plugin>\out.csv`, or a `/` path on a
  POSIX host) is judged by the same roots and the same symlink confirmation as
  a Bash redirect. The destination is bound by `-Path`, `-FilePath`,
  `-LiteralPath`, `-LP` or `-PSPath`, or given positionally, bare or single-quoted, and the write's
  only other arguments are `-Append`, `-Force`, `-NoClobber`, `-NoNewline` or
  `-NoTypeInformation`. Everything else keeps the block: a relative, `$`-carried,
  double-quoted, wildcard or comma-listed destination; any other flag; a second
  write; any variable, subexpression, script block, call operator, here-string,
  comment, `;` or launcher in the command.

  **On Windows the temp default takes an 8.3 short-name spelling** (since
  **0.38.6**), because that is how `TEMP`, and so the harness scratchpad, is
  spelled on a volume that generates short names (`C:/Users/<user>~1/...`,
  `RUNNER~1` on the Windows CI runner). A `~` is accepted only in a component of
  the 8.3 shape (`NAME~N`, `NAME~N.EXT`), and only for the temp default: the
  target must match a temp candidate's own spelling, which spends no resolver
  process, and then its resolved, fully expanded path must sit under a resolved
  temp root. A short component nothing backs (`name~9` that does not exist), an
  8.3 alias of a junction out of temp, a temp-rooted project, a leading `~`,
  `~user`, `~+`, and `x~` or `a~b` components all still block, and a configured
  scratch root never matches a `~` target. `secret-pattern-detection` declines
  a `Write` to the same spelling under the same rules. The staged-move detector
  compares a short and a long spelling of one file by their resolved paths, so
  `> <8.3 temp>/x && mv <long temp>/x src/a.py` blocks in both directions. On
  POSIX a `~` in a path is a filename byte and still blocks.

  **The memory tier is deliberately NOT a second default.** `<memory_dir>/`
  (default `.work/`) was exempted here during review and removed again, because
  the argument above does not carry to it: `secret-pattern-detection` scans a
  `Write` to `.work/notes.md` today, so exempting Bash redirects there would let
  `printf '<secret>' >> .work/notes.md` reach disk unscanned while the identical
  `Write` stayed blocked, the same content-guard bypass the MCP lane above
  exists to close. The consequence is that `printf '*' >> .work/.gitignore`
  still blocks because the memory tier is not exempt; write that file with
  `Write`, which the content guards scan.

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
  second shape hit an empty-`COMMAND` early exit and passed unexamined, and a real
  `C:\tmp\tmp.rSFIkHm5DO` was created on 2026-08-30 with no guard firing. Both
  shapes now feed the shipped `has_drive_root_tmp()`; there is no second matcher
  to drift. The file-path lane carries **none** of the command lane's
  string-matching floor, because it needs none: on `Write`/`Edit` the path is
  the write target by construction, so there is no redirect to parse, no
  producer-utility whitelist, and no quoted-prose ambiguity. Its residual is
  narrower than the command lane's and of a different kind: a path assembled at
  runtime and passed by a tool this guard does not match, either an MCP file-write
  tool or a Bash form the command lane's own residuals already allow.
- **`block-windows-drive-tmp`'s file-path lane shipped blocking on a measured
  sweep, per [ADR 0003](../../docs/adr/0003-verification-guards-earn-default-on-by-measured-precision.md).**
  Corpus: 259 distinct `file_path` / `notebook_path` values that a real `Write`,
  `Edit`, `MultiEdit` or `NotebookEdit` actually carried across 227 local Claude
  Code session transcripts on a Windows host, covering absolute Windows and MSYS paths,
  not the repo-relative ones a drive-root matcher could never match, which is
  what makes a low finding count informative here. **1 finding in 259 (0.39%
  firing), and it was a true positive**: `/tmp/tmp.rSFIkHm5DO/worktree-root`, the
  very write that produced the `C:\tmp\tmp.rSFIkHm5DO` this lane exists to stop.
  Six seeded spellings were detected end to end.

  **What that evidence does and does not support, stated plainly.** Precision is
  1/1, so the ratio is 100% and the sample is one. This is the ADR's
  near-zero-findings branch, where the seeded-detection burden carries the
  argument and the precision figure by itself does not. The corpus is one
  Windows host and one operator, so it is evidence about this deployment and
  weaker evidence about others; it contains no `MultiEdit` or `NotebookEdit`
  entries at all, and those two tools are covered by the contract suite and by
  the shared matcher, not by the sweep. **The ratio considered acceptable for
  this surface is a false-positive rate near zero, and the justification is that
  the cost of a wrong block here is unusually low**: the agent gets a stderr
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
  closed on a NUL anywhere in a file body, and that surface belongs to
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
- **Running a repo script under PowerShell: the form that passes.** On the
  PowerShell tool a launcher (`pwsh`, `powershell`, `cmd`, `Start-Process`) in a
  command that could reach git is the `ps-unparsable-launcher` fail-closed sink,
  so run the script in the tool's own session instead, where every guard reads
  it in full:
  `Set-Location <dir>; & ./<script>.ps1`. Set the directory first: a script
  that imports a module by a relative path resolves it against the current
  directory, not the script's, which is the `Import-Module` failure a bare
  `pwsh -File <script>` from another directory hits. Where only the Bash tool is
  available (an agent whose tool list omits PowerShell), the working shape is
  `pwsh -NoProfile -NonInteractive -WorkingDirectory <dir> -Command "& ./<script>.ps1; exit $LASTEXITCODE"`,
  with `exit $LASTEXITCODE` carrying the script's exit code back to Bash. The
  Bash lane does not parse inside that `-Command` string, so a git command
  written there is not guarded: run git as its own Bash command.

### Hook budget accounting

**0.41.1, repeat Edit/Write verifiers (#4390).** A second markdown edit at the same
HEAD does not re-walk deleted-path history, and a second skill reference at the
same manifests does not re-read every `plugin.json`. The deleted-path set is
keyed by the HEAD sha in the common git dir. The tracked-file list is reused
only while that cache is strictly newer than the index, and the plugin index
only while it is strictly newer than every manifest, so a same-tick rewrite is
read again. A failed history walk is not cached. Shallow clones are still
detected from `.git/shallow`.

**0.41.2, the remaining PostToolUse execs (#4390).** The cold finding fire's incidental `awk`, `tr`, and `cut` are gone: 25 process creations and execs to 19, and 19 to 13 on the second edit at the same HEAD. What remains on that fire is the shell, the dispatcher, and five `git` processes. The goal, the floor, and why the ideal k × S wall is below that floor are in [`reference/edit-write-guards/PLAN.md`](reference/edit-write-guards/PLAN.md).

The three report-only rows stay synchronous.

- **Decision**: do not set `async: true` on `cli-flag-verify`, `skill-reference-verify`, or `stale-path-verify`. These findings are advisory context for the edit that just landed, and an async row would deliver them after that edit, could lose them at the end of a `claude -p` run, and would not be bounded by the row's `timeout`. Blocking guards stay synchronous and fail closed.
- **Pointer**: for async delivery, `-p` teardown and `timeout` on an async hook, see <https://code.claude.com/docs/en/hooks#run-hooks-in-the-background> and <https://code.claude.com/docs/en/hooks#how-async-hooks-execute>.
- **As of**: 2026-09-28
- **Recheck trigger**: that section changes when async output is delivered beside the tool result, when `-p` waits for a running async hook, or when `timeout` applies to one.

**0.38.0, a long command (#4528).** 2026-09-27, Linux 6.12, bash 5.2.21,
en_US.UTF-8. The Bash/PowerShell row on a heredoc of prose, wall time for the
whole row: 10 KB **7.23 s -> 132 ms**, 16 KB (just under the ceiling)
**12.6 s -> 203 ms**, ~70 KB **still running at 120 s -> 64 ms**. The shared
tokenizer read the command one `${cmd:i:1}` at a time, and bash measures the
whole string on every one of those, so each parse was quadratic, and six
guards parsed the same command. It now splits the command in 4096- and 64-byte
blocks under the C locale (one parse of a 10,000-character heredoc:
1.27 s -> 84 ms), one parse is
replayed to the other five, and a command over `MAX_COMMAND_LEN` ends the chain
at `block-no-verify`, the first guard, whose ceiling refuses it unread. No
reported segment changed: the parse is byte-identical to the old one under
en_US.UTF-8, C.UTF-8 and C, and every guard suite passes on both paths.

**0.34.0, the in-process guard chain.** 2026-09-15, Windows 11 + Git Bash
(`usr\bin\bash.exe` as the hook shell), host idle. Process creations counted
exactly with a Windows job object around the harness's own invocation
(`bash -c "<hooks.json command>"`, PreToolUse payload on stdin), which counts
every fork and exec alike: on this host every command substitution is a
process, and an external command is two (the fork, then Cygwin's exec). Chain
of eight Bash guards, benign `true`: creations **23 -> 3**, isolated p50
**880 ms -> 297 ms** (n=5). The three that remain are the harness's `bash -c`,
the `env` its shebang goes through, and bash itself: the guards spawn nothing.
Same chain, PowerShell `exit 0`: **100 -> 80** creations, **3.3 s -> 2.4 s**;
the eighty are the `$(…)` captures and `printf | sed` pipelines inside
`lib/powershell/ps-command.sh`, which is the next cut. What was removed: the
eight isolation subshells (the guards are sourced into the dispatcher's shell
and `exit` is a function there), the `$(declare -f)` copy of `hook::jq_fields`,
the `printf | jq` process substitution that primed the fields (the library now
proves the common payload's fields with builtins and runs jq only when it
cannot), and the seven telemetry-subject captures. Decisions: byte-identical
rc, stdout and stderr against 0.33.11 over the perf baseline's 17-command
corpus in both tool modes (34 cases) and over every command harvested from the
eight guard suites.

**0.32.20, forks with no exec in `block-dangerous-git`.** 2026-09-06, Linux CI
host. A PATH shim counts execs, and a fork that never execs is invisible to
it. On every Bash and PowerShell call this guard created three such
processes and executed none. One was the guard's own, an eager telemetry
subject at file scope that the verdict never reads; it is now derived inside
`emit_tel`, behind the gates that keep the envelope off by default. Off the
common path, the hash-width probe `$(git ... 2>&1)` paid a second fork for
its in-substitution redirect (now `exec git ...`, the redirect stays inside
because git's stderr is what the block message quotes), and a `!` alias
reparse paid one `$(printf '%q')` per trailing argument plus one
`$(effective_dir ...)` (now `printf -v` and a nameref assignment). The two
creations that used to remain on the common path are `$(hook::buffer_stdin)`
and the shared parser's `< <(printf ...)`, both `lib/hook-utils.sh` work
that already landed (#3740, #3838), so the guard's own share on a benign
Bash call is now zero processes.
No verdict changed: 190 paired runs against `origin/main` agree on exit code
and stderr, and the 479-case contract suite passes. Those runs did not cover a
`PATH` carrying no `git`, and that is the one input whose stderr text moves:
the quoted probe diagnostic reads `exec: git: not found` where it read
`git: command not found`. The push is blocked either way.

*Method.* Kernel census, `strace -f -e trace=clone,clone3,fork,vfork,execve`,
on the dispatched path (`run-guards.sh block-dangerous-git.sh`), this
repository as cwd, `HOOK_TELEMETRY_SINK` unset, `CLAUDE_PROJECT_DIR` empty.
The guard's share is the count minus a no-op guard dispatched the same way.
Creations are clone-family returns; execve is counted separately so an exec
cannot pass for a removed fork. Three repeats, identical each time. Wall
clock is not reported: this host's spawn floor is under a millisecond and the
figure would not transfer to the Windows hosts the budget is written for; the
process count is the durable number.

| Counter | before | after |
|---|---|---|
| Guard share, benign `git status --short`: creations / execve | 3 / 0 | 0 / 0 |
| Guard share, blocked `git push --force origin main`: creations / execve | 3 / 0 | 0 / 0 |
| Guard share, lease `--force-with-lease=main:<40-hex>`: creations / execve | 5 / 1 | 1 / 1 |
| Guard share, `!` alias with three trailing args: creations / execve | 8 / 0 | 0 / 0 |
| Guard share, PowerShell `git status`: creations / execve | 15 / 3 | 14 / 3 |
| Whole Bash dispatcher, benign: creations / execve | 35 / 3 | 34 / 3 |

The execve column does not move, which is what makes this latency rather
than removed work. The two guard-share rows and the lease / alias pins are
current after merging #3838. The whole-dispatcher and PowerShell rows were
measured against this branch's base before #3838 landed, so they still carry
the dispatcher's own pre-fusion cost; the reduction that change made to the
dispatcher is recorded in the 0.32.11 row below, not here. The contract suite
pins the benign share, the lease probe and the alias reparse by the same
instrument.

**0.32.18, forks with no exec in `block-hook-bypass`.** 2026-09-06, Linux CI
host. Every earlier row in this section counts execs through a PATH shim, and
a shim cannot see a fork: `$(builtin-only function)`, `< <(printf ...)` and a
pipeline each create a process that never execs. On a benign Bash call this
guard created seven such processes and executed none. Six were in the guard
itself (an eager telemetry subject at file scope, a `$(strip_literals)`, four
process-substitution line loops); the seventh was `$(hook::buffer_stdin)`,
whose fork-free form is `lib/hook-utils.sh` work. That form landed in #3838
and this guard now calls `hook::buffer_stdin_to`, so all seven are gone and
the guard's own share on a benign Bash call is zero processes.
No verdict changed: 244 paired runs against `origin/main`
(61 commands, Bash and PowerShell payloads, standalone and dispatched, plus
70 KiB single-line and 3000-line commands) agree on exit code and first
stderr line, and the 611-case contract suite passes.

*Method.* Kernel census, `strace -f -e trace=clone,clone3,fork,vfork,execve`,
on the dispatched path (`run-guards.sh block-hook-bypass.sh`), this repository
as cwd, `HOOK_TELEMETRY_SINK` unset, `CLAUDE_PROJECT_DIR` empty. The guard's
share is the count minus a no-op guard dispatched the same way, which removes
the dispatcher's own stdin, jq and isolation forks. Creations are clone-family
returns; execve is counted separately so an exec cannot pass for a removed
fork. Three repeats, identical each time. Wall clock is p50/p95 of 20 samples
after 2 warmup, sides interleaved, on a host whose `bash -c :` floor is about
1 ms; the milliseconds are context, the durable figure is the process count.

| Counter | before | after |
|---|---|---|
| Guard share, benign `git status --short`: creations / execve | 7 / 0 | 0 / 0 |
| Guard share, blocked `echo hi > notes.md`: creations / execve | 10 / 1 | 4 / 1 |
| Whole Bash dispatcher, benign: creations / execve | 36 / 3 | 30 / 3 |
| Guard alone under the dispatcher, wall p50 / p95 (n=20) | 27.4 / 29.2 ms | 24.3 / 27.5 ms |
| Whole Bash dispatcher, wall p50 / p95 (n=20) | 51.6 / 60.4 ms | 48.2 / 49.6 ms |

The execve column does not move, which is what makes this latency rather than
removed work. The contract suite pins the guard's benign share at exactly 0 by
the same instrument, so the figure moves with the code rather than with this
table.

The two guard-share rows are current after merging #3838. The
whole-dispatcher and wall-clock rows were measured against this branch's
base before #3838 landed, so they still carry the dispatcher's own pre-fusion
cost; the reduction that change made to the dispatcher is recorded in the
0.32.11 row below, not here.

**0.32.17, forks with no exec in `block-noncanonical-commit`.** 2026-09-06,
Linux CI host. A PATH shim counts execs, and a fork that never execs is
invisible to it. On every Bash and PowerShell call this guard created two
such processes and executed none. One was the guard's own, an eager telemetry
subject at file scope that the verdict never reads; it is now derived inside
`emit_tel`, behind the gates that keep the envelope off by default. On the
blocked multi-line commit path, `$(effective_dir …)` and
`$(explicit_git_dir …)` each paid a fork for a builtins-only function (now
`effective_dir_to` and `explicit_git_dir_to`, nameref assignments), and off
the common path a `!` alias reparse paid one `$(printf '%q')` per trailing
argument (now `printf -v`) and the PowerShell lane paid `$(cd … && pwd)` for
the plugin root when `CLAUDE_PLUGIN_ROOT` was unset (now the path itself).
The shared parser's `< <(printf …)` in `lib/hook-utils.sh`, which held the
benign figure at one, went in 0.32.13 (#3878); on this guard a benign Bash
call now creates no process at all. No verdict changed: 218 paired runs
against `origin/main` (96 payloads: 85 Bash, 9 PowerShell, 2 Write-tool,
standalone and dispatched, plus 13 payloads under a `PATH` with no `git`)
agree on exit code, stdout and stderr, 11 telemetry envelopes agree on
subject and form, and the contract suite passes.

*Method.* Kernel census, `strace -f -e trace=clone,clone3,fork,vfork,execve`,
on the dispatched path (`run-guards.sh block-noncanonical-commit.sh`), this
repository as cwd, `HOOK_TELEMETRY_SINK` unset, `CLAUDE_PROJECT_DIR` empty.
The guard's share is the count minus a no-op guard dispatched the same way.
Creations are clone-family returns; execve is counted separately so an exec
cannot pass for a removed fork. Three repeats, identical each time. Wall
clock is p50/p95 of 20 samples after 2 warmup, sides interleaved, on a host
whose `bash -c :` floor is about 1 ms; the milliseconds are context, the
durable figure is the process count, and none of this was measured on a
Windows host. The "before" column is `main` at `1b681862`, after #3878
removed the parser fork; against the pre-#3878 `main` every creation count
below read one higher on both sides. The wall-clock rows were taken against
that earlier baseline (`c0fba152`) and not re-run.

| Counter | before | after |
|---|---|---|
| Guard share, benign `git status --short`: creations / execve | 1 / 0 | 0 / 0 |
| Guard share, single-line `git commit -m`: creations / execve | 1 / 0 | 0 / 0 |
| Guard share, blocked multi-line `git commit -m`: creations / execve | 5 / 1 | 2 / 1 |
| Guard share, non-builtin subcommand (`git wibble`): creations / execve | 6 / 2 | 4 / 2 |
| Guard share, blocked inline `!` alias: creations / execve | 10 / 3 | 6 / 3 |
| Guard share, PowerShell `git status`: creations / execve | 14 / 3 | 12 / 3 |
| Whole Bash dispatcher (eight guards), benign: creations / execve | 22 / 2 | 21 / 2 |
| Guard alone under the dispatcher, benign, wall p50 / p95 (n=20), vs `c0fba152` | 23.8 / 25.9 ms | 21.2 / 30.9 ms |
| Guard alone under the dispatcher, blocked, wall p50 / p95 (n=20), vs `c0fba152` | 32.2 / 75.8 ms | 29.9 / 44.7 ms |

The execve column does not move, which is what makes this latency rather
than removed work. The PowerShell lane's remaining creations are in
`lib/powershell/ps-command.sh`, not in this guard. The contract suite pins the
benign share, the blocked-path delta and the alias reparse by the same
instrument.

**0.32.16, the abort boundary.** 2026-09-07, Linux CI host. A correctness
change, not a perf one, recorded here because it touches every registered
hook's prologue: each now sources `hooks/abort-boundary.sh` and installs an
EXIT trap (#3528). Kernel census with
`strace -f -e trace=clone,clone3,fork,vfork,execve` of the whole Bash
dispatcher (eight guards) on a benign `git status --short`, three repeats each
side against `origin/main`: creations **23 -> 23**, execve **2 -> 2**. The
boundary adds no process: the trap is a builtin, the handler is builtins only,
and under the dispatcher each isolation subshell inherits the loaded library
and returns on its include guard. Wall clock, p50/p95 of 20 samples after 2
warmup, interleaved, two rounds: 59.9/65.1 and 61.7/63.3 ms before,
67.0/92.1 and 63.8/68.5 ms after, so about 2 to 5 ms at p50 on this host from
eight extra file opens. Not measured on a Windows host.

**0.32.14, leftover helper-capture forks on verifiers and PreToolUse
telemetry.** 2026-09-06, Linux CI host characterized measurable by
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
characterized measurable by `spawn_probe` (min 0.6 ms, spread 1.32×).
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
characterized measurable by `spawn_probe` (min 0.6 ms, spread 1.32×).
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
characterized as measurable. Wall clock is p50/p95 of 20 samples after 2
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
characterized as measurable (min 0.4 ms, spread 2.26×). Wall clock is
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
warmup on a host `spawn_probe` characterized as measurable (min 0.5 ms, spread
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
host `spawn_probe` characterized as measurable (min 0.5 ms, spread 1.42×).

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
the pattern" (hooks reference, `if` field, raw `hooks.md` fetched 2026-09-05). Recheck when the
hooks reference changes how the `if` field is evaluated or lets one handler hold several rules.
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
fires only on `mcp__github__push_files` and `mcp__github__create_or_update_file`, also under a plugin-bundled `github` server (`mcp__plugin_<plugin>_github__<tool>`), so
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
all-or-nothing per call: one filter it cannot serve sends the whole call to an
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
direct hook invocation with a benign representative payload, a `Write` of a
short body to an ordinary repo path, with sets launched concurrently (`&` + `wait`)
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
completeness and must not be read as a delta, because they do not resolve one:
`AFTER` measures *lower* than `BEFORE`, and adding a hook cannot make a set
faster. A separate **paired A/B** (n=15, BEFORE and AFTER launched back to back
inside each trial in alternating order so load drift biases both arms equally)
came out at a mean **1.26×**, but its per-trial ratios span **0.55×–1.82×**.
Several trials put AFTER *faster* than BEFORE, which is physically impossible
and is the host's noise, not the hook's cost. **On this host the set-level delta
is below the noise floor and this accounting does not state one.** What can be
said: the harness dispatches matching hooks in parallel, so the set wall is the
max of its members rather than their sum, and a member costing ≈ 505 ms joining
a set already walling at ≈ 1 s cannot raise that wall by more than its own cost
and will usually raise it by less. A re-measurement on a quiet reference host is
the way to replace this bound with a number, and is the honest follow-up.

**Share of the budget, and the overage.** The convention's ceiling is
≤ 1 s typical / ≤ 2 s worst-case **per tool call, counting `PreToolUse` and
`PostToolUse` together for one matcher**, so the surface this widening lands on
is larger than the table above measures: guardrails also runs three `PostToolUse`
verifiers on `Write|Edit`, and the fleet's binding accounting for the whole
per-`Write` set is **≈ 1.9 s** (two formatters plus three guardrails verifiers),
already over the typical ceiling before this change and deeper into overage than
the PreToolUse-only slice measured here suggests. Against that surface the
guard's own **≈ 505 ms is ≈ 25% of the ≤ 2 s worst-case ceiling as an upper
bound on its contribution**, and less than that in practice because it is
dispatched in parallel rather than added. Per the convention's rule 2 the budget
does not relax to absorb the overage: remediation is guardrails' own
spawn-reduction work (#1403), and this change pays part of its way: it removes
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
| check-bash-file-changes | `bash_file_change_check_enabled` |
| block-windows-drive-tmp | `block_windows_drive_tmp_enabled` |
| block-exported-msys-pathconv | `block_exported_msys_pathconv_enabled` |
| block-root-delete-target | `block_root_delete_target_enabled`, `block_root_delete_target_allowed_roots` |
| block-credential-read | `block_credential_read_enabled` |
| block-noncanonical-commit | `block_noncanonical_commit_enabled` |
| block-convention-violation | `block_convention_gate_enabled` |
| cli-flag-verify | `cli_flag_verify_enabled` |
| skill-reference-verify | `skill_reference_verify_enabled` |
| stale-path-verify | `stale_path_verify_enabled` |
| workflow-resilience-check | `workflow_resilience_check_enabled` |
| flag-commit-pr-skill-bypass | `flag_commit_pr_skill_bypass_enabled` |

Hook cost of the three verifiers: their PostToolUse rows (`.md`, `.sh`, `.bash`, `.ps1`,
`.psm1` edits) carry the launcher gate `--skip-if-all-false` over all three switches. With
`cli_flag_verify_enabled`, `skill_reference_verify_enabled` and `stale_path_verify_enabled` all
`false`, an edit starts node only, never bash. Any other value, one switch left on included, runs
the row as before, and each verifier still checks its own switch.

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
  whatever arrived, rather than let an unscanned tool call through; the same
  holds for text that is not JSON. The one allowed shape is a well-formed JSON
  prefix on a pipe that then **closes**: that is the harness's payload cut
  short in transit, a fault the command did not cause and the agent cannot
  stage, so the guard allows the call with a visible notice instead of
  blocking it. A stall on the same prefix is deliberately not given that
  allowance: payload size and host load both move it, so it stays a block, and
  some genuine stalls are still denied for it. On a shell whose `read -t`
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
  Secret scanning still declines a temp-tree file when the project dir is set
  and lies outside the temp tree, never wider than `block-hook-bypass`'s temp
  default.
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
- **Coverage manifest.** `hooks/coverage.json` declares, per guard, which
  baseline permission families and exact patterns it blocks by default (today
  `block-dangerous-git` covering `destructive-bash-deny`) and the levers that
  narrow or switch it off (`block_dangerous_git_enabled`,
  `block_dangerous_git_allow`). The `harness-config` plugin's `audit` skill reads
  it to demote a missing baseline deny pattern to `info` when the family is
  already blocked by a live hook, citing the manifest and naming the levers as
  the residual. It is data, never executed, and adds no per-call latency;
  `coverage-manifest.test.sh` pins it to the guards it describes.

## Telemetry (opt-in)

Every guard emits one structured [hook-telemetry](../../docs/conventions/hook-telemetry/README.md)
envelope per run to whatever `HOOK_TELEMETRY_SINK` names, carrying `status`
(`blocked` on a guard block, `ok` otherwise), `duration_ms`, and a privacy-safe
`data` payload (category **labels** only, never a secret value, matched path,
or full command). Unset `HOOK_TELEMETRY_SINK` → no-op; the guards behave exactly
as before.

## Requirements

- **bash 5.0+** and **jq**, the guards' runtime. Without **jq**, the guards that
  block irreversible operations deny every Bash and PowerShell call, with one
  line naming jq per call, and the other guards skip their work after one
  notice per session, never a silent disable.
- **Node.js** on `PATH`. Every guard row starts through `hooks/exec-bash.mjs`, which finds bash
  and runs the guard; the script declares no minimum Node version. The exec-form row needs `node`
  resolvable on `PATH`, and we treat a row that cannot start because `node` is missing as a guard
  that enforced nothing, with no documented error to rely on. `/guardrails:check` reports a missing
  `node` or `jq`. A `SessionStart` row in shell form
  (no `shell` field and no `args`) runs `lib/prerequisites.sh node-notice`, or
  `lib/prerequisites.ps1` where there is no `sh`, and needs no node itself. When node is
  absent it exits 0 with a `systemMessage` that shows the user a warning once per session across
  plugins, and the notice names `/guardrails:check`.
  It prints nothing when node is present. It does not read the per-guard toggles, because an unset toggle exports no
  environment variable and the row would need every guard's key listed by hand; a host that turns
  every guard off should disable the plugin instead. Pointer: for how an exec-form `command`
  resolves, see <https://code.claude.com/docs/en/hooks#exec-form-and-shell-form>; for a hook that
  cannot start, see <https://code.claude.com/docs/en/hooks#other-exit-codes>; for where
  `SessionStart` stdout goes, see <https://code.claude.com/docs/en/hooks#exit-code-0>; for
  `systemMessage`, see <https://code.claude.com/docs/en/hooks#json-output>. As of: 2026-10-01.
  Recheck trigger: the hooks page documents a `command` absent from `PATH`, or changes who sees
  `SessionStart` stdout or `systemMessage`.
- On Windows, **Git Bash** (the hooks run via Git Bash's bash).
- `cli-flag-verify` runs `<bin> --help` for the binaries it scans; findings
  require those binaries on PATH (missing binaries are skipped, never flagged).

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install guardrails@<marketplace>
```

Then verify the runtime prerequisites and live guard surface with
`/guardrails:check`; `/guardrails:setup apply` resolves anything the
check reports with guidance. Opt-in personal git hooks:
`/guardrails:setup apply install-commit-msg` (commit-convention depth layer) and
`/guardrails:setup apply install-pre-commit-content` (secret / hardcoded-path
content invariants on every staged blob, write-path-independent).

## Configuration

### Option details

**`block_dangerous_git_enabled`.** The `push --force-with-lease` case blocked is one that leases
against a value git resolves at push time, meaning either no expected value, or an expectation that
is not an object id of the repository's own hash width.

**`block_dangerous_git_allow`.** The full token set: `push-force`, `push-lease-unsafe`,
`reset-hard`, `clean-force`, `checkout-dot`, `restore-dot`, `checkout-force`, plus the PowerShell
fail-closed sink shapes `ps-unparsable-dynamic-invocation`, `ps-unparsable-launcher`,
`ps-unparsable-special-construct`, `ps-unparsable-herestring-unbalanced` and
`ps-unparsable-herestring-subexpr`. block-no-verify honors the same sink tokens, so one entry clears
a mutating block both guards hold; a command still unreadable after five granted sink rounds is
refused whatever the list holds. Empty blocks all.

**`block_hook_bypass_scratch_roots`.** The list adds to the two roots the guard already ships
exempt: the host temp trees, which the harness scratchpad sits under, and the plugin data directory
(`<config dir>/plugins/data`), where plugins persist their reports. Each is gated on
`CLAUDE_PROJECT_DIR` naming a project root that does not contain it. Set this to name a scratch
root of your own; the kill switch, not this option, is the whole-guard lever. The memory tier
(`<memory_dir>/`, default `.work/`) is deliberately NOT a shipped default: secret-pattern-detection
scans a Write there, so exempting Bash redirects to it would let a secret reach disk unscanned.
Matching is on the effective stdout target after lexical normalization, at a path-component
boundary, so a sibling merely sharing the name prefix, a `..` escape out of a root, and a
discard-then-real-file redirect all still block. A relative target is resolved against the tool
call's own cwd and refused when the command carries a cd/pushd/popd. On the Bash tool a quoted or
escaped OPERAND is never exempt: the operand is marked so it survives the quote strip and the
segment split as one word, and an operand carrying whitespace, `;`, `|`, `&`, `(`, `)`, a newline
or a backslash escape exempts nothing. Quotes elsewhere in the command no longer matter. On the
PowerShell tool only a command that is one write to one absolute destination, bare or
single-quoted, with no variable, subexpression, call operator or second write, is exempt. Symlinks
are not followed for a CONFIGURED root (an operator naming a root accepts its contents); the
shipped temp default resolves them before exempting.

**`block_windows_drive_tmp_enabled`.** One switch covers both lanes: Bash/PowerShell commands and
Write/Edit/NotebookEdit file paths. On Git for Windows, a Bash-tool `/tmp` that
cygpath/mount shows is the usertemp mount of `%TEMP%` is not blocked; `/c/tmp`, `C:\tmp`,
drive-root `\tmp`, PowerShell `/tmp`, and the file-path lane still are. `curl -o`/`--output` and
`wget -O`/`--output-document` destinations are judged the same way as cp/mv.

**`block_exported_msys_pathconv_enabled`.** Either shape switches off conversion for later
commands, letting an unconverted `/d/...` reach git as `<current-drive>:\d\...`; a prefix on a
non-shell command word and a bare assignment are not matched.

**`block_root_delete_target_enabled`.** Blocks a Bash recursive `rm` whose target normalizes to a
filesystem root: `/` and `/*`, the MSYS-translated bare backslash (`rm -rf "\\"` and a dangling
`rm -rf \`, the shape that cost a whole volume in anthropics/claude-code#92593), `~`, a literal
`$HOME` / `${HOME}`, a drive root (`C:\`, `c:/`, `C:`), an MSYS, WSL or cygdrive drive root (`/c`,
`/mnt/c`, `/cygdrive/c`), and a UNC share root (`//server/share`). A recursive `rm` carrying
`--no-preserve-root` is refused whatever it targets, and long options are matched on any
unambiguous prefix as coreutils reads them. The command word is resolved through a launcher and its
operand-taking options (`sudo -u bob rm`), and a child shell's operand is re-parsed
(`bash -c '...'`). Quoted prose that merely names such a command is not matched, because the
command word of that segment is not `rm`. It also refuses an empty operand (`rm -rf ""`), a bare
variable operand (`$X`, `"$X/"`, `"$X"/*`, `$X$Y`, any `${...}` form but `"${X:?}/"`), and, when the
payload carries a cwd, a target that resolves outside the payload cwd's git toplevel and is not
strictly under a temp root, the session scratchpad or a root you list in
`block_root_delete_target_allowed_roots` (`rm -rf ../../..`, `rm -rf ~/Documents/x`,
`cd / && rm -rf *`, `rm -rf /c/Users/*/.claude`, a `link/` that points outside). Braces are
expanded and each alternative judged (`rm -rf {/c,x}`), a glob before the last component is
expanded and each match judged as a literal path, and a relative path after a cd it can read but
not follow (a relative cd while CDPATH is set, a glob target with no match or several) is refused.
The judgment is bounded (512 targets, 256 glob entries, 25 seconds of wall time) and refuses past a
bound. A target it cannot place (an expansion other than HOME, a relative path after a non-literal
cd) is left alone. On the PowerShell tool the same target classes are refused for
`Remove-Item -Recurse` (and aliases `ri`/`rm`/`rd`/`rmdir`, with `-r`/`-rec` as unambiguous
prefixes) and for `cmd /c rd /s` / `rmdir /s`, without loading the shared PowerShell classifier.

**`block_root_delete_target_allowed_roots`.** The list ADDS TO the temp roots and the session
scratchpad the guard already allows. Only you set it: it is read from the hook's own environment,
never from the command text, so an agent cannot grant itself a root with a `VAR=...` prefix or a
flag. Targets are compared by real path, so a symlinked root or target is judged where it lands, a
sibling that only shares the name prefix is refused, and a symlink under a root that points outside
it stays refused. A listed root itself and its glob are refused, like a temp root. Every other
refusal stays in force whatever is listed: a filesystem root, `~`, `$HOME`, a drive root, a UNC
share, `--no-preserve-root`, an empty or bare-variable operand, a glob that escapes, and a `..`
escape. An entry that is relative, empty, UNC, holds a glob character, a line break or a `..`
component, or resolves to a filesystem root or HOME grants nothing, and no listed root lets through
HOME or a directory holding it. The kill switch, not this option, is the whole-guard lever.

A **name-prefix entry** ends in one `*` after a literal name, for example `D:/worktrees/.tmp-*` for
the throwaway test directories agents create beside their worktrees. It allows only a direct child
of that directory whose name starts with the text before the `*` and has at least one more
character (`D:/worktrees/.tmp-6527`), and never one that is itself a symlink. It refuses the
directory, the bare prefix (`.tmp-`), a sibling (`D:/worktrees/other-worktree`), anything below a
matching child, a glob such as `rm -rf D:/worktrees/.tmp-*`, and a `..` escape. It also refuses a
name ending in a dot or a space, which Windows trims (`.tmp-.` names `.tmp-`), and a trailing-slash
operand whose child does not exist yet, because a link the same command creates would be followed. The `*` marks the
form because an entry holding a glob character granted nothing before, so no entry that already
allowed something changes meaning. The directory follows the rules above, and a name with any other
glob character grants nothing. An alternative that needs no entry: point the user-level `TEMP` or
`TMPDIR` at a directory on the drive you want, which the guard already treats as a temp root.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `secret_pattern_detection_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_SECRET_PATTERN_DETECTION_ENABLED` | Blocks writes containing high-confidence secret or credential patterns. On by default. |
| `hardcoded_path_check_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_HARDCODED_PATH_CHECK_ENABLED` | Blocks writes containing hardcoded machine-specific paths. On by default. |
| `block_no_verify_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BLOCK_NO_VERIFY_ENABLED` | Blocks git hook-bypass attempts: --no-verify, core.hooksPath=, and hook-manager env-var disables for a configurable set (lefthook, husky, pre-commit and simple-git-hooks by default). On by default. |
| `block_no_verify_hook_manager_prefixes` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_BLOCK_NO_VERIFY_HOOK_MANAGER_PREFIXES` | Comma-separated hook-manager env-var name prefixes block-no-verify treats as a bypass when set to 0 or false (e.g. lefthook,husky). Empty, the default, uses the built-in set: lefthook, husky, pre_commit, simple_git_hooks. |
| `block_dangerous_git_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ENABLED` | Blocks irreversible git operations: push --force, reset --hard, clean -f, worktree-wide checkout or restore discards, and a push --force-with-lease that leases against a value git resolves at push time. On by default. The README's Option details define the lease case. |
| `block_dangerous_git_allow` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW` | Comma-separated forms block-dangerous-git permits: push-force, push-lease-unsafe, reset-hard, clean-force, checkout-dot, restore-dot, checkout-force, plus the PowerShell ps-unparsable-* sink tokens the README's Option details list. Empty, the default, blocks all. |
| `block_credential_read_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BLOCK_CREDENTIAL_READ_ENABLED` | Blocks a Bash or PowerShell command whose output is a credential: git credential fill and credential-helper get, gh auth token, echo or printenv of a token-shaped variable, and cat of .git-credentials, .netrc or .env. On by default. |
| `block_credential_read_allow` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_BLOCK_CREDENTIAL_READ_ALLOW` | Comma-separated families block-credential-read permits: credential-fill, gh-auth-token, env-echo, credential-file-read. Empty, the default, blocks all. |
| `block_hook_bypass_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BLOCK_HOOK_BYPASS_ENABLED` | Blocks Bash file-write workarounds that circumvent Write and Edit hook gates. On by default. |
| `block_hook_bypass_scratch_roots` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_BLOCK_HOOK_BYPASS_SCRATCH_ROOTS` | Comma-separated absolute directories block-hook-bypass exempts as scratch or temp write targets (e.g. /tmp/scratch,/d/jobtmp/session). Empty by default; it adds to the shipped temp-tree and plugin-data roots. Matching, quoting and symlink rules are in the README's Option details. |
| `bash_file_change_check_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BASH_FILE_CHANGE_CHECK_ENABLED` | After a Bash or PowerShell command, runs the Write and Edit secret and hardcoded-path guards on each repository file the command changed, and reports what they find. On by default. |
| `block_windows_drive_tmp_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BLOCK_WINDOWS_DRIVE_TMP_ENABLED` | Blocks writes to a Windows drive-root temp path (/tmp, C:\tmp, \tmp, /c/tmp) that resolves to <drive>:\tmp instead of %TEMP%, in shell commands and Write/Edit file paths alike. On by default. The Git for Windows exception is in the README's Option details. |
| `block_exported_msys_pathconv_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BLOCK_EXPORTED_MSYS_PATHCONV_ENABLED` | Blocks a leaking MSYS path-conversion suppressor on Windows: an exported MSYS_NO_PATHCONV or MSYS2_ARG_CONV_EXCL, or one prefixed on a child shell (MSYS_NO_PATHCONV=1 bash -c ...). On by default. What it does not match is in the README's Option details. |
| `block_root_delete_target_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BLOCK_ROOT_DELETE_TARGET_ENABLED` | Blocks a recursive delete (rm, Remove-Item, rd /s) whose target is a filesystem, home, drive or UNC share root, an empty or bare-variable operand, or a path outside the repo not under a temp root, the scratchpad or an allowed root. On by default. Full rules in the README's Option details. |
| `block_root_delete_target_allowed_roots` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_BLOCK_ROOT_DELETE_TARGET_ALLOWED_ROOTS` | Comma-separated absolute directories; a recursive delete passes when its real path is strictly under one. An entry like D:/worktrees/.tmp-* allows only direct children whose name extends that prefix. Empty by default; adds to the temp roots and scratchpad. Limits: README Option details. |
| `block_noncanonical_commit_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BLOCK_NONCANONICAL_COMMIT_ENABLED` | Blocks git commit -m when the message contains a newline (pipe it via -F - instead); a single-line -m passes. On by default. Exempt: --amend, -C/-c, --fixup/--squash, -F <path>, and an in-progress merge or rebase. |
| `block_noncanonical_commit_allow` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_BLOCK_NONCANONICAL_COMMIT_ALLOW` | Comma-separated form tokens block-noncanonical-commit permits. The only token today is message-flag, which permits -m even when the message contains a newline. Empty, the default, permits none. |
| `block_convention_gate_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BLOCK_CONVENTION_GATE_ENABLED` | Blocks a commit subject or gh pr create --title that violates the team-tracked convention pattern in .claude/source-control.md. On by default; with no tracked pattern nothing is enforced. Same exemptions as block-noncanonical-commit. |
| `cli_flag_verify_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_CLI_FLAG_VERIFY_ENABLED` | Advises on hallucinated CLI flags written to files; never blocks. On by default. |
| `cli_flag_verify_bins` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_CLI_FLAG_VERIFY_BINS` | Comma-separated binaries cli-flag-verify scans. Empty, the default, uses the built-in set. |
| `cli_flag_verify_skip_bins` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_CLI_FLAG_VERIFY_SKIP_BINS` | Comma-separated binaries cli-flag-verify must never scan. Empty by default. |
| `skill_reference_verify_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_SKILL_REFERENCE_VERIFY_ENABLED` | Advises when markdown cites a /plugin:skill reference this repo owns but cannot resolve; never blocks. On by default. |
| `stale_path_verify_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_STALE_PATH_VERIFY_ENABLED` | Advises when markdown cites a repo-relative path this repo's own history shows was removed and that is gone from the working tree; never blocks. On by default. |
| `workflow_resilience_check_enabled` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_WORKFLOW_RESILIENCE_CHECK_ENABLED` | Advises on un-throttled Workflow fan-out; never blocks. Off by default since 0.20.0: a behavioral-class prose injector, config-disabled per the instruction-economy evidence gate (#2021). Set true to opt back in. |
| `flag_commit_pr_skill_bypass_enabled` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_FLAG_COMMIT_PR_SKILL_BYPASS_ENABLED` | Advises when a direct gh pr create bypasses the source-control pull-request skill; never blocks. Off by default since 0.20.0: a behavioral-class prose injector, config-disabled per the instruction-economy evidence gate (#2021). Set true to opt back in. |
| `stdin_read_timeout` | number<br>*min 1* | `2` | `CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT` | Idle bound on reading the hook payload from stdin: how long a silent pipe is tolerated before a blocking guard fails closed. Default 2. Only a JSON payload the pipe closed on mid-document is allowed with a notice; a stalled pipe stays a block. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure guardrails@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
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

3. **By hand, in settings.** Add the value under `pluginConfigs` in your **user**
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
   only, **not** from a project's `.claude/settings.json`. To vary behavior per
   repository, enable or disable the plugin in that project's `enabledPlugins`
   instead of setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
