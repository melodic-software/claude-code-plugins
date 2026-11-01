# guardrails

A Claude Code plugin bundling sixteen **safety guards** that catch risky agent
actions the moment they happen, before a write lands or a bash command runs, and
three git-hook checks that cover every commit and push. Each guard is independently
toggleable, so you run exactly the subset you want.

## Contents

- [The guards](#the-guards)
  - [Git hooks](#git-hooks)
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
were eight, one per Write/Edit PreToolUse where there were three, each started by
the node entry), the exit code (2 if any guard blocks, and every
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
spelling, unless the whole command is one `cat`, `gh`, `git commit -F -` or `git tag -F -`
line feeding it. For a body that gives it nothing to judge (`$(: rm)`) its 25-second
deadline never starts, so the 16384-character
command ceiling bounds the cost: 2.6 to 3.7 s measured. Unquoted, double-quoted and unquoted-heredoc-body substitutions still
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
| **block-no-verify** | PreToolUse · Bash \| PowerShell | **Blocks** (exit 2) | Git hook-bypass attempts on `git commit` / `git push`: `--no-verify` / `-n`, `core.hooksPath=` assignment, and hook-manager disable env vars, a configurable prefix set defaulting to `lefthook`, `husky`, `pre_commit`, `simple_git_hooks` (e.g. `LEFTHOOK=0`, `HUSKY=0`, `PRE_COMMIT_*=false`), tunable via `block_no_verify_hook_manager_prefixes`, including inside compound `cd … && …` commands. Also a persistent `git config core.hooksPath <dir>` in any scope, unless `<dir>` is exactly `.githooks`, the directory plain shared git hooks live in, set at local scope while `.githooks/` holds the guardrails dispatcher: a real directory whose `pre-commit`, `pre-push` or `commit-msg` is a regular file, not a symlink, with the line `# checks-dispatcher v1`. The marker is trusted as is, since `.githooks` only runs content a merged change controls; it keeps the guard from approving the key where guardrails is not installed. Known residual: the check reads the working directory, not a `cd other &&` target, so that compound sets the key in a clone whose `.githooks/` it never checked, whose commits then run whatever that directory holds, or no hooks if it is missing. `git -c checks.skipmissing=<tool>`, the check-placement skip key a git-hook check honors only for a missing tool, is allowed. |
| **block-dangerous-git** | PreToolUse · Bash \| PowerShell | **Blocks** (exit 2); **asks** instead when `CLAUDE_CODE_SESSION_ATTENDED` is `1` | Irreversible git operations: `push --force`/`-f` plus the equivalent leading-`+` refspec and `--mirror` forms, and the unsafe `--force-with-lease` spellings, in the two kinds git itself treats differently. **No expected value** (bare `--force-with-lease` or `=<refname>`) leases against the remote-tracking ref, which git documents as "trivially defeated" by a background fetch, blocked unless `--force-if-includes` is present, which git documents as the mitigation for exactly this form. **A movable `=<refname>:<expect>`**, such as `origin/main`, `HEAD`, a tag, an *abbreviated* object id, or hex of the wrong width for this repository's hash format, all of which git resolves at push time, and gitrevisions resolves a short hex word as a ref before trying it as an object-id prefix, is blocked unconditionally, because git declares `--force-if-includes` a no-op alongside an explicit `:<expect>`. A lease passes only when `<expect>` is immutable: a **literal** object id of the pushed repository's own hash width (detection never evaluates substitutions, so resolve it with `git rev-parse` as a separate step and pass the result) (40 hex under SHA-1, 64 under SHA-256, read from `git rev-parse --show-object-format` with the command's own `-C`/`--git-dir`/`--work-tree`/`--namespace` replayed onto it; undeterminable fails closed) or the empty string asserting the ref must not exist. The other width is a ref name there, not an object id. git ignores a ref whose name is full-width hex for its own format, but resolves one of the other width like any name. git scopes a pin to its own ref, so a bare fallback alongside a pinned entry still governs every other ref being updated; where the same ref carries several lease entries, git consults the first, and so does this guard. A trailing `--no-force-with-lease` cancels every previous lease, and a push dry-run disarms the check. Also blocked: `reset --hard`, `clean` with a force flag (any dry-run flag disarms; on the Bash tool, a plain `git reset --hard` or `git clean -f` passes when git places both the work tree's top level and the common git directory under the system temp directory (`$TMPDIR`, `$TMP`, `$TEMP` or `/tmp`; `/var/tmp` persists across reboots, so it counts only when one of those variables names it) and `HOME` is not under it, and the command is that one git invocation alone, with no `-c` global, wrapper, alias, separator, quote, escape, expansion, redirection or glob), worktree-wide `checkout`/`restore` pathspecs (`.`, `:/`, `:(top…)`; path-scoped forms and `restore --staged .` pass), and forced `checkout -f` / `switch --discard-changes`. Accepted unique-prefix abbreviations of the blocked long options match too. `branch -D` is deliberately not blocked (reflog-recoverable; sanctioned skill flows issue it). Per-repo/per-user allow-list via the `block_dangerous_git_allow` userConfig option (comma list, any subset of `push-force,push-lease-unsafe,reset-hard,clean-force,checkout-dot,restore-dot,checkout-force`). |
| **block-windows-drive-tmp** | PreToolUse · Bash \| PowerShell **and** Write \| Edit \| NotebookEdit | **Blocks** (exit 2) | Windows-only: write targets that are a drive-root temp path: POSIX `/tmp`, MSYS `/c/tmp`, `C:\tmp`, or drive-root `\tmp`, which resolve to `<drive>:\tmp` instead of `%TEMP%` and accumulate at the volume root. On a stock Git for Windows install the Bash-tool POSIX `/tmp` is a `usertemp` mount of `%TEMP%` itself, so that spelling is not blocked there; `/c/tmp`, `C:\tmp`, `\tmp`, PowerShell `/tmp`, and the file-path lane still are. On the **command lane** redirects and write utilities (`mkdir`/`mktemp`/`tee`/`cp`/`curl -o`/`--output-dir` (bare or bundled, as in `-sSLo`)/`wget -O`/`Set-Content`/`Out-File`/…) are blocked; on the **file-path lane** (since **0.30.0**) the tool's own `file_path` / `notebook_path` is matched directly, because on a Write the path *is* the write target. Both lanes call one matcher, so the same spellings block and the same ones pass. Does not fire on non-Windows hosts; leaves `%TEMP%` / `$TEMP` / `$TMPDIR` / `$env:TEMP` / `/var/tmp`, relative `./tmp`, `foo/tmp`, `/tmpdir`, `C:/tmp2` and UNC `\\server\tmp` alone. Covers the `tmp` spellings only: `C:\Temp` and other `Temp` directories are not matched. Inline python `open (` and `getattr(__builtins__,'open')(` count as writes, except a provable read: a bare one-argument `open(` (optional read-only mode `r`/`b`/`t`, optional literal `encoding=`/`errors=`/`newline=`) followed by `.read(`/`.readline(`/`.readlines(` or wrapped whole in `json.load(`, e.g. `json.load(open('/tmp/x.json'))`. That exemption is judged over the whole unsplit command, never per segment, and applies only when that command is one plain python run (`python`, `python3` or `py` with plain flags) whose code is its `-c` string or a heredoc on stdin, with no pipe, `;`, `&&`, redirect, argument, wrapper, second command or later line, so a pipeline cannot lift the path out of the text and write it (`echo "open('/c/tmp/x').read()" \| cut -d "'" -f2 \| xargs tee`): every `open` in the command must be such a read and no drive-root temp path may remain outside those calls, so a decoy read beside a write (`os.system`, `shutil.copy`, a second `open(..., 'w')`, a heredoc body) still blocks. Fail-closed: the method form (`Path(...).open()`), a variable or non-read mode, an argument that is not a plain path (a leading pipe that Ruby's `open` runs as a subprocess, `%x[...]`, `#{...}`), an argv operand, any `\`, `$` or backtick in the command, and indirection (`exec`, `eval`, `getattr`, `subprocess`, `os.popen`, ...) keep the block. Quoted `open(` / `write_text(` text counts as data only when the whole command, with every quoted string replaced by one placeholder word, is exactly one of `gh issue` or `gh pr` with `create`, `comment` or `edit`, `git commit`, `git tag`, `echo` or `printf`, with plain flag words, on the Bash tool and with no `\`, `$`, backtick, operator, newline, glob or redirect, so `gh issue create --body "...open('/tmp/x','w')..."` passes while any other command, including an interpreter this guard does not know, blocks. The read exemption also keeps the block when the token `tmp` remains outside the read calls. A deterrent over one command string, not a sandbox: concatenated or computed paths pass. |
| **block-exported-msys-pathconv** | PreToolUse · Bash \| PowerShell | **Blocks** (exit 2) | Windows-only: an **exported** `MSYS_NO_PATHCONV` / `MSYS2_ARG_CONV_EXCL` (also the `declare -x` / `typeset -x` spellings), which switches off MSYS argv rewriting for every *later* command in the same command string. A later path argument then reaches a Windows-native program unconverted and git resolves its leading `/` against the current drive, so `git worktree add /d/worktrees/x` creates `<current-drive>:\d\worktrees\x` (#2870). Deliberately keys on the environment, not on a path shape: the incident command's path argument was identical to one that had already worked. A prefix whose command word is a **shell** (`MSYS_NO_PATHCONV=1 bash -c '…'`, `env … sh -c '…'`) blocks too: the prefix scopes to one *process*, and when that process is an interpreter, one process is every command inside it. A prefix on a **non-shell** command word (`MSYS_NO_PATHCONV=1 git show …`) and a bare assignment are not matched. The first scopes to exactly that command, and the second has no effect at all because the MSYS runtime reads the environment. Does not fire on non-Windows hosts. |
| **block-cd-prefix** | PreToolUse · Bash | **Blocks** (exit 2) | A command that opens with `cd <path>` followed by `&&`, `;` or a newline, where a later segment runs `git` (by basename, after any `NAME=value` prefix) or writes (`>`, `>>`, `<>`, `>&`) to a relative path. That shape matches no permission allow rule, so it prompts or is refused; the reason says to run `git -C <abs path> ...` with absolute paths, and to pass a multi-line commit message with `git commit -F <file>`. `cd .`, a `cd` to the payload `cwd`, a `cd` joined by `\|\|` or `\|`, and a write to an absolute path, a `$` path or an fd (`2>&1`) pass. Not matched: a `&>` or `>\|` write, and git behind a wrapper (`sudo git`). Fails open when it cannot read the payload. |
| **block-root-delete-target** | PreToolUse · Bash \| PowerShell | **Blocks** (exit 2); **asks** instead when `CLAUDE_CODE_SESSION_ATTENDED` is `1` and it read the target | A recursive `rm` whose target normalizes to a filesystem root. The command is parsed the way the shell builds argv, through launchers (`sudo`, `env`, `timeout`, the util-linux family including `setpriv` and `prlimit`, `systemd-run`), child shells (`bash -c`, `su -c`, `sg`), `eval` and command substitutions, and a segment is judged when its command word is `rm` with a recursive flag. A `find` whose expression deletes is judged the same way: `find -delete`, or an `-exec`, `-execdir`, `-ok` or `-okdir` whose command word is `rm`, `rmdir` or `unlink`. Each start point is a target, `.` when none is given, read the way GNU and BSD find both read their leading options, so `find / -delete` and `find ~ -exec rm -rf {} +` are refused and `find build -name '*.o' -delete` passes. Under `-H`, `-L` or `-follow` a start point that is a symlink is judged by where it points. A find delete started at the git toplevel is refused as a directory holding a `.git` whatever its filters, because find descends into `.git`. `xargs` and `parallel` running a recursive `rm` or a deleting `find` are judged too: the command's own operands and parallel's `:::` items as written, and the items they read only when a confined listing produced them, through `grep`, `sort`, `uniq`, `head` or `tail` at most. A `find` without `-printf`, `-fprintf`, `-ls`, `-fls`, an `-exec`-family action or `-files0-from` has its start points judged, and `git ls-files` with no git option and no `--format` is judged as a name strictly under the directory it runs from. Items from a file (`xargs -a`, `parallel ::::`), from the shell's own stdin or from any other command are refused, so `cat list \| xargs rm -rf` is refused and `find build -name '*.o' \| xargs rm -rf` passes. An `rsync` that deletes is judged the way a recursive `rm` operand is: its destination (the last operand) with `--del`, `--delete` or a `--delete-<mode>`, and every source before it with `--remove-source-files`. So `rsync -a --delete src/ /` and `rsync -a --delete src/ ~` are refused, and `rsync -a --delete src/ build/out` passes. A remote operand (`host:path`, `rsync://`) is left alone. A `robocopy` that deletes is judged the same way, from the Bash and the PowerShell tool (`cmd /c robocopy` included): its destination (the second operand) with `/MIR` or `/PURGE`, and its source (the first) with `/MOVE` or `/MOV`, so `robocopy src / /MIR` and `robocopy ~ out /MOVE` are refused and `robocopy src build/out /MIR` passes. A `git worktree remove` with `-f` or `--force` is judged the same way: its `<worktree>` operand, by real path, and every registered worktree whose path ends in that text, because git looks a worktree up by its trailing path components first. So `git worktree remove --force /` and `git worktree remove --force ~` are refused, and `git worktree remove --force build/wt` passes. A registered worktree root stays protected, as for `rm`, unless it is not the git toplevel and sits strictly under a temp root, the session scratchpad or an allowed root; a relative `<worktree>` after `git -C`, `--git-dir` or `--work-tree` is refused. A move or a content destroyer is judged the same way ([#9767](https://github.com/melodic-software/claude-code-plugins/issues/9767)): each source an `mv` moves away (every operand but the last, or every one with `-t`), onto `/dev/null` included, and each file `truncate` or `shred` names or `dd of=` writes (`/dev/null` and the standard streams aside). So `mv ~ /dev/null`, and `truncate -s 0 /etc/hosts` or `dd if=/dev/zero of=/dev/sda` from a repository, are refused, and `mv build/x out/` passes. On the PowerShell tool the same holds for `Move-Item` (`mi`, `move`, `mv`) and `Clear-Content` (`clc`), by each `-Path` or `-LiteralPath` element, and for a `Set-Content` that writes several files (a comma list, or a wildcard in `-Path`); a `Set-Content` of one file is an ordinary write and is not judged. Interpreter code is read too: the program a `python -c`, `node -e`, `perl -e` or `ruby -e` runs, and one such an interpreter reads from a heredoc or a here-string (`python3 - <<'EOF'`). A call to its language's deleter (`shutil.rmtree`, `os.remove`, `fs.rmSync`, `FileUtils.rm_rf`, perl `rmtree` and their siblings) has each string-literal path judged the way a recursive `rm` operand is, so `python3 -c "import shutil; shutil.rmtree('/')"` and one aimed at `$HOME` or outside the allowed roots are refused, and `shutil.rmtree('build/x')` passes. A path the code computes (`shutil.rmtree(sys.argv[1])`) is refused, because the guard cannot place it. A command the code runs (`os.system`, `subprocess.run`, `child_process.execSync`, `system`, a backtick) is judged as the shell or the program receives it. A string or comment in the code that names a deleter is not a call. A decoder feeding an execution sink is refused outright, whatever the decoded text targets, and an attended session is denied too, because the decoded text never appears in the command: `base64 -d`, `base32 -d`, `basenc -d` or `xxd -r` whose output a shell reading stdin, `source /dev/stdin`, `eval`, a `-c` operand or a substitution in command position runs (`echo <b64> \| base64 -d \| sh`, `eval "$(echo <b64> \| base64 -d)"`, `bash <(xxd -r -p dump.hex)`, `$(echo <b64> \| base64 -d)`), and `[Convert]::FromBase64String` reaching `Invoke-Expression` or `iex` on the PowerShell tool. Decoded output written to a file or shown in a pager (`base64 -d x > out.bin`, `base64 -d x \| less`) passes, and so does a decoder named inside quoted prose. On the Bash tool a delete run through `eval`, `watch`, `wsl`, `cmd /c` or a shell that reads its program from stdin is judged as the delete itself, the way the `sh -c` and `env -S` unwrapping judges one ([#9768](https://github.com/melodic-software/claude-code-plugins/issues/9768)): the words `eval` joins, the command `watch` hands `sh -c` (or runs as argv with `-x`), the command line `wsl` hands the distribution's shell, `rd /s`, `rmdir /s` and `robocopy` in the line `cmd /c` or `cmd //c` runs, a code heredoc or here-string a shell reads (`bash <<'EOF'`), and the text `echo`, `printf` or a `cat` of a heredoc pipes into a shell (`echo 'rm -rf /' \| sh`). So `watch rm -rf ~`, `cmd //c rd //s //q 'C:\'` and `echo 'rm -rf /opt/x' \| sh` from a repository are refused, and `eval 'rm -rf build/x'` passes; the same mechanism named in quoted prose (`git commit -m "echo 'rm -rf /' \| sh"`) stays allowed. Roots: `/` and `/*`, the MSYS-translated bare backslash in both its quoted (`rm -rf "\\"`, the shape behind the whole-volume loss in anthropics/claude-code#92593, which no permission pattern keyed on `rm -rf /*` matches) and **dangling** (`rm -rf \`) spellings, `~`, a literal `$HOME` / `${HOME}`, a drive root (`C:\`, `c:/`, `C:`), an MSYS, WSL or cygdrive drive root (`/c`, `/mnt/c`, `/cygdrive/c`), and a UNC share root (`//server/share`). `--no-preserve-root` is refused whatever it targets. Also refused: an **empty operand** (`rm -rf ""`), a **bare variable operand** made of expansions alone (`$X`, `"$X/"`, `"$X"/*`, `$X$Y`, any `${...}` form but `"${X:?}/"`; a variable is judged as a plain literal only when the command opens with `NAME=LITERAL` and one `&&`, `;` or newline, nothing later in it can change `NAME` (a second assignment, or a builtin or syntax that sets a variable by name), and every `$NAME` in it is a whole double-quoted word, `"$NAME"` or `"$NAME/..."` with a plain suffix inside the quotes (an unquoted `$NAME` binds nothing, since an inherited IFS can split it), with no other quote, escape, expansion, glob or brace in the command, as in `S=/tmp/x; mkdir -p "$S/a"; rm -rf "$S"`), and, when the payload carries an absolute `cwd`, a target **outside the session's allowed roots**: not under the git toplevel of the payload cwd, and not strictly under a temp root, the session scratchpad or a root you list in `block_root_delete_target_allowed_roots` (`rm -rf ../../..`, `rm -rf ~/Documents/x`, `cd / && rm -rf *`, `rm -rf {/c,x}`, `rm -rf /c/Users/*/.claude`, a `link/` that points outside). Ahead of those roots a **protected tree** is refused even inside one: a `.git` (named, or globbed straight inside, as in `rm -rf .git/*`), a directory holding a `.git`, the git toplevel itself, a worktree root git has registered, anything under `~/.claude`, Claude Code's temp tree outside this session's own scratchpad (its base, a project or session directory, another session's scratchpad), and anything under a directory listed in `block_root_delete_target_protected_trees`. A directory holding any of these is refused too; a path named under the toplevel, a worktree or `.git` is not (`rm -rf build`, `rm -rf .git/rebase-merge`), nor is the toplevel's own bash glob (`rm -rf *`, which skips dot names). Not host-gated. The guard's header in `hooks/block-root-delete-target.sh` lists how braces, globs, directory changes and symlinks are judged, the bounds past which it refuses, the known false positives, and the declared gaps. On the PowerShell tool the same classes are refused for `Remove-Item -Recurse` (aliases `ri`/`rm`/`rd`/`rmdir`, prefixes `-r`/`-rec`) and for `cmd /c rd /s` / `rmdir /s`, without loading the shared PowerShell classifier ([#4516](https://github.com/melodic-software/claude-code-plugins/issues/4516)). Each statement is judged, including one after a newline and one inside a `{ }` scriptblock, a `( )` grouping or `$( )`, and a `Remove-Item` target that is a grouping is refused. `$env:NAME` and `${env:NAME}` are judged as the Bash lane judges `$NAME`: refused bare or followed only by `\` or `\*`, allowed with a named subpath (`$env:TEMP\build`). A target whose every `$` is literal (single-quoted or backtick-escaped) is also judged as the path it names, and a Win32 stream suffix such as `::$INDEX_ALLOCATION` as the directory before it; this only adds refusals, so a target refused when every `$` read as an expansion (`'$env:TEMP'`) is refused still ([#6626](https://github.com/melodic-software/claude-code-plugins/issues/6626)). A PowerShell delete run through another command is judged as the delete itself ([#9765](https://github.com/melodic-software/claude-code-plugins/issues/9765)): the string `Invoke-Expression` or `iex` runs (its `-Command`, or a string piped to it), the `-Command` or `-CommandWithArgs` text of `pwsh` or `powershell`, a `-EncodedCommand` decoded from base64 of UTF-16LE, the program and `-ArgumentList` of `Start-Process` (`saps`, `start`), a pipeline removal (`gci X \| Remove-Item`, `gci X \| % { $_.Delete() }`, through `Where-Object`, `Sort-Object` or a `Select-Object -First`) by the `Get-ChildItem` or `Get-Item` path that feeds it, and a .NET delete (`[IO.Directory]::Delete`, `[IO.File]::Delete`, `(Get-Item X).Delete()`) by its path argument. So `Start-Process cmd '/c rd /s /q C:\'`, `pwsh -Command 'Remove-Item -Recurse $HOME'` and `[IO.Directory]::Delete('D:\x', $true)` from a repository are refused, and `gci build \| Remove-Item -Recurse` passes. A removal fed by anything but such a listing is refused, and so are a grouping, array or call as a .NET delete's path and `.Delete()` on a grouping that is not one listing; an `-EncodedCommand` that is not literal base64 of printable ASCII text is denied, attended or not. Not covered: a command that is not the first word of its statement (`$r = Remove-Item -Recurse C:\`), a comma list of `Remove-Item` targets, a here-string, a find action that runs its deleter through a launcher or a child shell (`-exec sudo rm`, `-exec sh -c 'rm …'`), the action command's own operands (`-exec rm -rf /x \;`), a symlink below a start point that `-L` or `-follow` makes find follow, find start points read with `-files0-from`, a `;` or `&&` between a listing and `xargs` (read as a pipe), `xargs` splitting a listed path at a blank or a quote (`-print0` with `-0` keeps it whole), an abbreviated rsync long option, the paths an rsync `--files-from` list names below a source, the options and paths a robocopy `/JOB` file supplies, a git alias that runs `worktree remove`, `git worktree remove` on the PowerShell tool, a script file an interpreter runs or one piped into its stdin, a deleter reached through an alias, a renamed import (`from os import remove`) or a path object's method (`Path(p).unlink()`), interpreter code on the PowerShell tool, decoded text carried to its sink through a variable or a file (`x=$(base64 -d f); eval "$x"`), a decoder this guard does not name (`openssl base64 -d`), an `iex` string or a `Start-Process` program or argument list held in a variable or built by a grouping or `@( )`, a `.Delete()` object held in a variable, `pwsh -File` and `pwsh -Command -`, the file `mv` or `Move-Item` overwrites at its destination, an output redirection (`> file`), a `Set-Content` of one file, a `find` action that runs `mv`, `truncate` or `shred`, and, from the Bash tool, `powershell -Command Remove-Item`, a command in a `cmd /c` line other than `rd`, `rmdir` and `robocopy` (`del /s`), a `%NAME%` that line expands, a delete after a `cd` on it, and a program a shell reads from a file or through a filter (`cat x.sh \| sh`, `echo x \| tr a b \| sh`). |
| **block-credential-read** | PreToolUse · Bash \| PowerShell | **Blocks** (exit 2). **Off by default**: `block_credential_read_enabled` turns it on | A command whose output is a credential: `git credential fill`, credential-helper `get`, `gh auth token`, `echo`/`printenv` of a token-shaped variable, `jq env` (every variable), an interpreter's inline code or heredoc (`python3 -c`, `node -e`, `ruby -e`, `perl -e`, `php -r`) reading `.git-credentials`, `.netrc`, `.env`, `.credentials.json`, `.docker/config.json`, `~/.ssh/id_*` or `~/.aws/credentials`, PowerShell `Get-Content` of one, and `jq` of the two JSON files. `cat`, `head`, `tail` and the Read tool on those files are left to native `Read()` deny rules, which `/guardrails:setup apply install-read-deny` prints. Presence checks such as `gh auth status` and `test -n "$GH_TOKEN"` pass. The guard header in `hooks/block-credential-read.sh` lists the known gaps and false positives. Escape: `block_credential_read_enabled` (off switch) or `block_credential_read_allow` (comma list of `credential-fill`, `gh-auth-token`, `env-echo`, `credential-file-read`). |
| **block-cross-domain** | PreToolUse · Bash \| PowerShell | **Blocks** (a `deny` decision on stdout, exit 0); a malformed map is reported to the user once per session | From a session whose `cwd` is in one identity domain, a command that names another domain's path, a read as much as a write, or puts another domain's identity marker in an identity position. From every session, in a domain, neutral or on a host with no map, a command that writes the machine's git identity: a `git config` with `--global`, `--system` or `--file <identity file>` that sets, adds, replaces or unsets `user.email`, `user.signingkey`, `user.useConfigOnly`, `credential.helper` (also `credential.<url>.helper`), `core.sshCommand`, `core.hooksPath` or an `includeIf` key, renames or removes the section holding one, or opens `--edit`; and a shell write to an identity file (a redirection, `tee`, `touch`, `truncate`, `rm`, `unlink`, `shred`, `mv`, the destination of `cp`, `install`, `ln`, `rsync` or `scp`, `sed -i`, `perl -i`, `dd of=`, and the PowerShell writers such as `Set-Content`, `Out-File`, `Remove-Item` and `Copy-Item -Destination`). An identity file is `~/.gitconfig*`, any `*.gitconfig`, and each path in the map's `identity_files` with every path below it. Reads pass: `--get` and the other `--get-*` forms, `--list`, `git config get` and `list`, the old form with a key and no value, and a command that only reads the file. The domains come from a machine-local map, `${CLAUDE_PLUGIN_DATA}/identity-domains.json`. Config shape: `domains.<name>` holding `roots` (absolute roots per OS, keyed `linux`, `macos` and `windows`), `owners`, `identity_markers` and optional `gh_config_dir` and `az_config_dir`, then top-level `identity_files`, `shared_exceptions` (entries `{"path": <dir>, "from": [<domain>], "to": <domain>}`) and `messages`. Only `domains` and each domain's `roots` are required, and an unknown key makes the map malformed. `/guardrails:setup apply identity-domains` writes it from the identity domains `/harness-ops:machine-profile` recorded, after you confirm, and asks for the owners, markers, `az_config_dir` and shared exceptions the profile lacks; you can also write it by hand. Keep it out of every tracked file. With no map the guard checks identity writes alone, and parses only a command whose text holds both `git` and `config`. With one, it compiles the map with `jq` into `identity-domains.cache` beside it once per change of the map or of `HOME`, classifies the session `cwd` into the domain whose path holds it (the longest path wins) or neutral, and tests the command text, quotes dropped, for each path and marker; only a command that names one is parsed. A domain's paths are its roots and, for each owner, `~/src/github.com/<owner>` and `~/worktrees/github.com/<owner>`, matched in any case and spelled as written, as a Windows drive path with either slash or escaped backslashes, in the MSYS (`/c/...`), Cygwin (`/cygdrive/c/...`) and WSL (`/mnt/c/...`) forms of a drive path, or, below `HOME`, after `~`, `$HOME` or `%USERPROFILE%`. The deny reason names the session's domain and the others. A marker in a path's place never denies; from a `cwd` in a domain, a command is denied that puts another domain's `identity_markers` entry in an identity position: the URL or name of `git remote add` or `set-url`, the value of `git config` or `git -c` for `user.email`, `user.name`, the `author.*` and `committer.*` keys or `remote.<name>.url`, `git commit --author`, and an assignment to `GH_CONFIG_DIR`, `AZURE_CONFIG_DIR` or a `GIT_AUTHOR_*` or `GIT_COMMITTER_*` variable (`NAME=value`, `export`, `env`, PowerShell's `$env:NAME =`). That deny's reason names the identity position. Only `identity_markers` entries are matched there. Setup fills `gh_config_dir` from the profile but adds a marker only for each `--marker` you give it. The same marker anywhere else, a commit message or an `echo`, is allowed, and a marker the session's own domain also lists never denies. A domain's `gh_config_dir` and `az_config_dir` are matched against the directory each `gh` and `az` call runs with: the `GH_CONFIG_DIR` or `AZURE_CONFIG_DIR` the command sets for it (`NAME=value` before it or after `env`, an earlier `export`, `unset` or PowerShell `$env:NAME =`), else the one in the hook's own environment. From a `cwd` in a domain with a `gh_config_dir`, a `gh` call that does not run with it is denied; from a domain with none, which uses the default, a `gh` call that runs with another domain's is denied; `az` likewise. `gh --version` and `az --version` are exempt, and a directory compares in any case, with `~` or `$HOME` read as `HOME`. From a neutral `cwd` nothing but an identity write is denied. A shared exception opens one directory of its `to` domain to sessions in its `from` domains, one way: from a `from` domain, a command that names the directory or a path below it is allowed when every other domain's path it names is inside the directory too and its text holds no `..`; any character right after the directory's name other than `/`, whitespace or a word-ending operator (`;&\|<>()`), such as a glob, brace or expansion (`shared*`, `shared{,-x}`) or one that continues a sibling's name (`shared+x`, `shared~x`), denies it too. A session in `to`, or in a domain `from` does not list, gets nothing from it. The `path` must be a path of `to` on this host, outside every domain nested there; one that is not, or an entry left as a plain string from the earlier shape, grants nothing, leaves the map well formed, and is named in a once-per-session notice that says to re-run setup. The telemetry envelope records `cwd` (`domain` or `neutral`), `form` (`prefilter-miss`, `not-named`, `own-domain`, `other-domain`, `identity-deny`, `config-deny`, `identity-write-deny` or `map-malformed`) and status `blocked` for a denied call, never a domain name; its `subject` is the command word, as in every guard's envelope. Declared gaps: it reads command text, a deterrent and not a sandbox, so it does not see a computed path (a variable, a substitution, a path spelled in pieces), a script run by name, a heredoc body (even one a shell runs), a path relative to the cwd or a symlink into a root, nor an identity position, an identity write or a `gh` or `az` call inside a `bash -c` or `sh -c` operand. A malformed map, or no `jq` on the hook `PATH`, turns the whole guard off, the identity-write rule included. The guard header in `hooks/block-cross-domain.sh` has the full map rules. Kill switch: `block_cross_domain_enabled`. |
| **block-unresolved-pr-merge** | PreToolUse · Bash \| PowerShell **and** `mcp__<server>__merge_pull_request` \| `mcp__<server>__enable_pr_auto_merge` | **Blocks** (exit 2) | A pull-request merge while the PR has an unresolved review thread (outdated ones included), a reviewer whose latest decisive review requests changes, or a failed check run or commit status on its head commit (only the newest run of each check by creation order counts, so a run a later run of the same check superseded does not block; a skipped or neutral run never supersedes a completed run with a real conclusion, though it does supersede a pending or cancelled one; a cancelled run is also superseded by a newer successful run of the same app, in another check suite, named `<name> (...)` (a skipped, neutral or failed leg does not clear it), since a matrix job cancelled before it expanded reports under its bare name, and an unrelated workflow's `<name> (...)` job in another suite clears it too, which the check-runs payload cannot tell apart; a check listed in `merge_guard_ignored_checks` as `<app slug>:<name>`, by default `github-actions:merge`, the pr-merge lane's own job, is never judged, and since a check run does not name its workflow, every GitHub Actions job named `merge` is ignored by that default; a failed run whose failure annotation says it was `superseded by full run <url>/actions/runs/<id> in flight on <head sha>`, as the contract-only ci-status does, does not count: that full run's run of the same check decides, and the check is pending until it exists); a pending check blocks an immediate merge but not an auto-merge or merge-queue request, which waits for checks by design. Merge paths: `gh pr merge` with any flags (`--admin` and `--auto` included), a `PUT` to `repos/{owner}/{repo}/pulls/{n}/merge` or to the Claude Code cloud route `pulls/{n}/ccr/auto_merge` through `gh api` or `curl`, the `mergePullRequest`, `enablePullRequestAutoMerge` and `enqueuePullRequest` GraphQL mutations through `gh api graphql` or `curl`, and the GitHub MCP server's merge tools under any server prefix. PR state is read over REST; review-thread resolution, which REST does not expose, comes from GraphQL where it is served and from the cloud route `pulls/{n}/ccr/review_threads` where GraphQL is refused (Claude Code on the web). Fails open with a notice to both the user and Claude when `gh` is missing or unauthenticated, a read fails, or its 35 s read budget runs out (kept under the row's 60 s timeout). An unresolvable target fails closed: a `gh pr merge` or REST merge whose repo or PR number comes from a shell variable, `$(...)` or backticks, or a bare `gh pr merge` whose current branch cannot be read or has no open PR, is blocked with the fix of writing `gh pr merge <number> -R owner/repo` literally. So is, on the Bash tool, a command whose text is merge-shaped (`pr merge` after a word that is `gh` or cannot be read, such as `g""h` or `$GH`, a `pulls/.../merge` route, a merge mutation name; prose such as "Gated PR Merge" is not) and holds a backtick anywhere, quoted or not (pass a body that holds one with `--body-file`), a `pr merge` or REST merge route continued with a backslash-newline (write the merge on one line; the command is never rewritten), and a command holding more than one merge (run each merge as its own command). The backtick and backslash-newline tests skip the body of a quoted heredoc (`<<'EOF'`) fed to a program that is not a shell, such as `python3 - <<'EOF'` or `git commit -F - <<'MSG'`; the guard header lists when a body is still read. So is a `gh pr` subcommand or a `-X` method taken from an expansion on a merge route (`gh pr $VERB`, `-X "$M"`), and a `gh pr merge` with no `-R` or URL in a command that also runs `cd`, `pushd` or `popd` or names `GH_REPO`, since it then merges outside the session's repository. A `-R HOST/OWNER/REPO` is read without its host (a host other than github.com goes to `gh api --hostname`), a quote-split `gh pr mer"ge"` is parsed, a branch name is percent-encoded into the lookup, and a 404 on a repo the command wrote is blocked instead of run unchecked. So is a GraphQL merge mutation whose PR cannot be resolved (an id from a variable or `$(...)`, or more than one id bound to `pullRequestId`), with the fix of passing a literal `PR_...` id. Only the id bound to `pullRequestId` is checked, never a `PR_...` in another field. In a Claude Code cloud session GraphQL is refused, so every GraphQL merge mutation is blocked there; use `gh pr merge <number>`. A `curl -T` / `--upload-file` to the merge route counts as a `PUT`. `gh pr merge --help` and `--disable-auto` are not merges. Not covered: a merge from a script (Python, Node) or the web UI; the org ruleset requiring conversation resolution is the server-side backstop. A merge pays five REST calls, plus one per failed check run (three at most) to read its annotations, measured at 3.0 to 3.6 s in a Claude Code cloud session; any other command pays one string test. The guard header in `hooks/block-unresolved-pr-merge.sh` lists the known gaps. Escape: `block_unresolved_pr_merge_enabled` (off switch); `merge_guard_ignored_checks` (comma list of `<app slug>:<name>` checks never judged; empty judges all). |
| **block-fix-request-post** | PreToolUse · Bash \| PowerShell **and** the GitHub MCP comment, review, issue and pull-request write tools (`mcp__github__add_issue_comment`, `pull_request_review_write`, and the rest named in `hooks/hooks.json`) | **Blocks** (exit 2) | An agent posting the PR-fix lane fix request: a line starting `PR-fix lane: please fix this finding`, any case, which the address-feedback lane (`FIX_REQUEST` in `.github/scripts/pr-unblock/address-feedback.mjs`) acts on with push credentials when someone with write access posts it. A local session posts with the owner's token, so only the owner posts it, typed in the GitHub UI ([#8438](https://github.com/melodic-software/claude-code-plugins/issues/8438)). Covers `gh pr\|issue comment\|review\|create\|edit`, a writing `gh api` (GraphQL only for a mutation), and `curl` with a body to a GitHub API route; the body is read inline, from heredocs, and from every `--body-file`, `-F k=@file`, `--input`, `-d @file`, `cat` or `<` file. A line after `>`, inside a fence, or a mention later in a line passes, as does a command that only reads or greps the phrase. The guard header lists the known gaps. Escape: `block_fix_request_post_enabled`. |
| **cli-flag-verify** | git pre-push, `reference-verify` entry, on `.md`, `.sh`, `.bash`, `.ps1`, `.psm1` | **Fails the push** (exit 1) | Hallucinated CLI flags: a `--flag` written as a command, on a line the pushed commits add, that does not exist in the binary's actual `--help` output. |
| **workflow-resilience-check** | PreToolUse · Workflow | **Advisory** (exit 0) | Workflow fan-out with no wave cap of its own: a script calling `parallel()` / `pipeline()` with no wave-cap throttle (`inWaves` / `inWavesPipeline`) and no retry wrapper (`agentRetry`), which risks a burst 529 under wide Opus fan-out. The runtime's own concurrency limit still applies ([workflows: Behavior and limits](https://code.claude.com/docs/en/workflows#behavior-and-limits), as of 2026-10-31; recheck when that limit or its default changes). Surfaces a one-line advisory via `additionalContext` that points at the workflow-authoring skill and names the overloaded-retry backoff ceiling variable with a link to its docs section, never blocks. **Opt-in. Default off since 0.20.0** (behavioral-class injector config-disabled per #2021; set `workflow_resilience_check_enabled=true` to enable). |
| **block-noncanonical-commit** | PreToolUse · Bash \| PowerShell | **Blocks** (exit 2) | `git commit -m` whose message holds a `$` or a backtick the shell expands before git sees it: double-quoted or unquoted in Bash (`$x`, `$(...)`, backticks), double-quoted in PowerShell (`$x`, and a backtick escape such as `` `f ``), and a PowerShell `@"` here-string. A newline alone is no hazard, so a plain message passes, multi-line included, and so do single quotes, fully escaped double quotes, Bash `"$(cat <<'EOF' ... EOF)"` and a PowerShell `@'` here-string; `-F -` / `--file -` is always safe. Exempt: `--amend`, `-C`/`-c`/`--reuse-message`/`--reedit-message`, `--fixup`/`--squash`, `-F <path>`, and any commit taken while a merge/rebase/cherry-pick/revert is in progress. Resolves `bash -lc` wrappers and git aliases (inline `-c` and persisted config alike). |
| **block-convention-violation** | PreToolUse · Bash \| PowerShell | **Blocks** (exit 2) | A commit subject or `gh pr create --title` that violates the team-tracked convention pattern declared in `docs/conventions/source-control.yaml` (for one release, else `.claude/source-control.md`). No tracked pattern means no enforcement. Same exemptions as `block-noncanonical-commit`. |
| **flag-commit-pr-skill-bypass** | PreToolUse · Bash \| PowerShell | **Advisory** (exit 0) | Any `gh pr create`, bypassing this marketplace's own `/source-control:pull-request` skill. Only fires when the consuming project's own `.claude/settings.json` enables the `source-control` plugin, and is silent otherwise. Surfaces via `additionalContext` once per session and agent, never blocks. **Opt-in. Default off since 0.20.0** (behavioral-class injector config-disabled per #2021; set `flag_commit_pr_skill_bypass_enabled=true` to enable). |
| **skill-reference-verify** | git pre-push, `reference-verify` entry, on `.md` | **Fails the push** (exit 1) | A `` `/plugin:skill` `` reference in markdown that does not resolve. Only fires inside a marketplace repo, and only for a plugin that repo's own manifests own. A reference to another marketplace is left alone. Resolves through manifest and frontmatter `name`, so a renamed directory still matches. |
| **stale-path-verify** | git pre-push, `reference-verify` entry, on `.md` | **Fails the push** (exit 1) | A repo-relative path cited in a markdown inline code span that this repo's own history shows was **deleted** and that is gone from the pushed tip's tree. The gate is provenance, not absence: the exact path must appear in `git log HEAD --no-renames --diff-filter=D --name-only`, so a path belonging to a consuming project's tree, an example, or a plan is never adjudicated. Names the surviving file when exactly one tracked path now carries that basename. Link destinations are out of scope. |

The blocking guards feed their stderr message back to Claude as
actionable fix guidance. The two advisory guards surface their findings the same
way but always allow the operation. `block-cross-domain` blocks through a PreToolUse
`deny` decision on stdout and exits 0, so Claude reads its reason from that decision,
which names the domains a path belongs to, the identity position, the config directory or the identity write; it speaks to the user only
when it cannot run its checks (a malformed map; a missing `jq`, the plugin's shared jq
notice).

### Git hooks

Three checks run as git hooks, so they cover every commit and push in the
repository, from Claude, a person, an IDE or another agent, and report at commit or
push time rather than after each edit. `/guardrails:setup apply install-git-hooks [scope=local|shared]`
registers them with the repository's hook manager (lefthook, husky or plain git
hooks) under the check-placement convention's contract
(`docs/contracts/check-placement/README.md` in the marketplace repository): local
scope is this clone only. Shared scope with lefthook adds one `remotes:` entry to the
committed `lefthook.yml`, so every clone runs the hooks from this marketplace repository's
`main` branch (`git-hooks/lefthook-remote.yml`), refetched hourly: whoever can merge to that
`main` runs code in every such clone within an hour, with its user's privileges and git
credentials. With husky or plain hooks it commits copies under
`.githooks/guardrails/`. A clone whose fetched remote no longer parses (every commit and
`lefthook install` then fail with a YAML error) recovers, once the fix is on `main`, with
`rm -rf "$(git rev-parse --git-path info)"/lefthook-remotes/claude-code-plugins-* && lefthook install`.
Each entry blocks only on what the commit or push adds. A clone that does not want an
entry declines it through `/guardrails:setup` (`install.mjs decline --entry <name>`),
which also removes the entry's registration when it is already installed. Every entry
starts under `sh` and never starts a `bash` by name, which on Windows can be System32's WSL
launcher; `commit-msg-convention` and its resolver are POSIX sh throughout, so they need no
bash beside git's sh.

| Entry | Event | What it checks |
|-------|-------|----------------|
| `commit-msg-convention` | commit-msg | The subject against the team-tracked `subject_pattern` in `docs/conventions/source-control.yaml` (for one release, else `.claude/source-control.md`), the pattern `block-convention-violation` reads. No tracked pattern, no enforcement. |
| `pre-commit-content` | pre-commit | Secrets and machine-specific paths on the lines the commit adds, with the same pattern libraries and path exemptions as `secret-pattern-detection` and `hardcoded-path-check`, so a file a shell command or script wrote meets the same checks as a Write. |
| `reference-verify` | pre-push | `cli-flag-verify`, `skill-reference-verify` and `stale-path-verify` on the lines the pushed commits add, through `hooks/run-guards.sh`. A new branch is judged from its merge-base with the default branch. Any pushed range then starts instead at the nearest of the remote's tracking refs between its base and its tip, so a stacked branch's push does not re-verify the pushed branches below it. Those tracking refs are trusted as verified without a check, including another author's branch, fetched into this clone, that was pushed with `--no-verify`. It skips files in a `samples/` folder below an `evals/` folder, which hold recorded model output; the rest of an eval suite stays checked. It runs at push rather than commit because it costs about 10 s on a 44-file change, over the commit budget (the check-placement convention's measured rows). Needs `jq`; the scanned binaries follow `CLAUDE_PLUGIN_OPTION_CLI_FLAG_VERIFY_BINS` and `CLAUDE_PLUGIN_OPTION_CLI_FLAG_VERIFY_SKIP_BINS` when set in the pushing environment. A cli-flag finding is unverified, not proven wrong, so its failure names the way out: decline the entry. The entry reads that decline itself, so it also stops on the lefthook remote, where no registration is removed. Each finding names the line holding the flag, path or reference. `git -c checks.skipmissing=jq` skips it only while `jq` is missing. Over ssh, the connection to the remote stays idle while the hook runs. A remote that drops an idle connection leaves a push that reports success but creates no ref. To keep the connection open, set `ServerAliveInterval` (for example `15`) for that host in the ssh config, or set it for one push: `git -c core.sshCommand="ssh -o ServerAliveInterval=15" push`. |

### Enforceability tiers

Most guards are **deterministic**. Their oracle is a mechanical test with no
judgment step. Two checks are **detect-then-judge**, where the oracle is mechanical but
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
Both kinds of path are absent locally
and conventionally shaped, so that class is deliberately
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
  `block-noncanonical-commit`, `block-convention-violation`,
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
- **Forced `git clean` has one owner: `block-dangerous-git`.** It blocks a
  forced clean outside the exceptions its row lists (a dry-run flag, a clean
  wholly under the temp directory, the `clean-force` allow-list entry).
  `block-root-delete-target` has no `git clean` arm and never judges a clean's
  target, so one guard decides the command and a clean is never allowed just
  because its target sits inside the session's tree.
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
- **A shell write is checked at commit time, not when it runs.** The Write and
  Edit content guards (secret patterns, hardcoded paths) see only those tools.
  A file a shell command, a script or an interpreter writes reaches them at
  commit time instead, through the `pre-commit-content` [git hook](#git-hooks),
  or through an equivalent CI check.
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
- **The Bash row fails open on a guard's crash.** An internal script error
  exits 0 so a defect on this hottest-path row cannot freeze the session, with
  the user notice so the allow is not silent. Stdin timeout and a NUL payload
  still fail closed. The row sets `"onFailure": "block"`, so on Claude Code
  2.1.295 or later a handler killed at its 60s `hooks.json` `timeout` denies
  the call; an older client lets it proceed. Pointer:
  <https://code.claude.com/docs/en/hooks#block-the-action-when-a-hook-fails>.
  As of: 2026-10-30. Recheck trigger: that section changes what a timed-out
  `PreToolUse` command hook does to the tool call. The plugin also keeps the
  row far from that bound, so a slow command gets the guard's own reason: the command
  tokenizer is linear in the command's length, one parse serves every guard,
  and a command over `MAX_COMMAND_LEN` is refused by the first guard that
  carries the ceiling before anything tokenizes it (#4528).
- **A dispatcher that ends without a verdict denies the call.** Every guard
  row passes `hooks/exec-bash.mjs --fail-closed --require-verdict` (#7681).
  `--fail-closed` denies a signal or any exit other than 0 and 2. Under
  `--require-verdict` the launcher names a marker file in
  `EXEC_BASH_VERDICT_FILE`, `run-guards.sh` writes it as its last action at
  each deliberate exit, and an exit 0 with no marker is denied: Windows Git
  Bash reports a crashed bash (a stack overflow, 0xC0000005) as exit 0 with
  empty output, which used to read as an allow. An abort in the dispatcher's
  own code writes no marker either, so it is denied too. A guard's own crash
  still settles through the boundary above, and the chain finishes with its
  verdict.
- **The content guards cover the GitHub MCP write lane; the scope is exactly two
  tools.** `secret-pattern-detection` and `hardcoded-path-check` inspect
  `mcp__github__push_files` (every entry of its `files` array, not just the
  first) and `mcp__github__create_or_update_file`, and, since **0.37.1**, the
  same two tools from a plugin-bundled GitHub server, matched as
  `mcp__plugin_<plugin>_github__<tool>`. Pointer:
  <https://code.claude.com/docs/en/hooks#match-mcp-tools>. As of: 2026-09-27.
  Recheck trigger: that section changes how a plugin-bundled server's tools are
  named. This closes a real hole. A
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
  `hardcoded-path-check` still resolves its scan root, so it catches this
  machine's own checkout path appearing verbatim in content being pushed.
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

- **`block-windows-drive-tmp` checks two write routes with one matcher, and only the
  command route was checked before 0.30.0.** A write reaches the drive root either as a
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
- **`block-windows-drive-tmp`'s file-path lane shipped blocking in 0.30.0
  (2026-08-31) on a measured sweep, per [ADR 0003](../../docs/adr/0003-verification-guards-earn-default-on-by-measured-precision.md).**
  Corpus: 259 distinct `file_path` / `notebook_path` values that a real `Write`,
  `Edit`, `MultiEdit` or `NotebookEdit` actually carried across 227 local Claude
  Code session transcripts on a Windows host, covering absolute Windows and MSYS paths,
  not the repo-relative ones a drive-root matcher could never match, which is
  what makes a low finding count informative here. **1 finding in 259 (0.39%
  firing), and it was a true positive**: `/tmp/tmp.rSFIkHm5DO/worktree-root`, the
  very write that produced the `C:\tmp\tmp.rSFIkHm5DO` this lane exists to stop.
  Six seeded spellings were detected end to end.

  **What that evidence supports and what it does not.** Precision is
  1/1, so the ratio is 100% and the sample is one. This is the ADR's
  near-zero-findings branch, where the seeded-detection burden carries the
  argument and the precision figure by itself does not. The corpus is one
  Windows host and one operator, so it is evidence about this deployment and
  weaker evidence about others; it contains no `MultiEdit` or `NotebookEdit`
  entries at all. `NotebookEdit` is covered by the contract suite and the shared
  matcher, not by the sweep; the matcher no longer names the legacy `MultiEdit`.
  **The ratio considered acceptable for this surface is a false-positive rate
  near zero, and the justification is that the cost of a wrong block here is
  unusually low**: the agent gets a stderr line naming `%TEMP%` and reissues
  the write, which is a second of friction,
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
- **`block-cross-domain` keeps its map and cache in the plugin's data
  directory.** `${CLAUDE_PLUGIN_DATA}` is `~/.claude/plugins/data/<id>/`, created
  on first reference and kept across plugin updates; uninstalling the plugin from
  the last place it is installed deletes it, map included, except in the cases the
  uninstall reference lists, such as `--keep-data`. Pointer:
  <https://code.claude.com/docs/en/plugins/manifest-reference#environment-variables>.
  As of: 2026-10-24. Recheck trigger: that section moves the directory or changes
  when it is deleted. Both files name this machine's trees and identities, so
  neither belongs in a repository, a fixture or a doc. The cache is keyed by the
  map's bytes and `HOME`: an edited map, or another `HOME`, is compiled again on the
  next call, and deleting the cache is always safe. `GUARDRAILS_CROSS_DOMAIN_TRACE=1` in the hook environment
  writes the steps a call reached to stderr, which the contract suite reads.

### Hook budget accounting

**block-root-delete-target shells and launchers from Bash (#9768).** The arm starts no process of its
own, so its k is 0: the text `eval` joins, `watch` runs, `wsl` hands its shell, `cmd /c` runs and a
stdin shell reads (a heredoc, a here-string, or what `echo`, `printf` or `cat` pipes into it) is
parsed in-process as a `bash -c` operand is, and an `echo`'s escapes and a `printf`'s output are
expanded by the `printf -v` builtin. Each target it then judges takes the path a recursive `rm`
operand takes, so with a payload cwd the call has the k a recursive `rm` has (4 in the #9752 census:
`git`, `realpath` and two `timeout`), and a call whose nested text judges no target keeps its k. The
Bash prefilter now also passes a command whose text holds `cmd` followed by `rd` (as do the
in-process checks on a substitution body, interpreter code and a `parallel` item), so such a call
pays the tokenizer parse. The measured wall time is recorded under #5946.

**block-root-delete-target moves and content destroyers (#9767).** The arm starts no process of its
own: it reads the argv of `mv`, `truncate`, `shred` and `dd` from the parse the guard already makes,
and the paths of `Move-Item`, `Clear-Content` and `Set-Content` from the statement walk, and each
judged source or file takes the path a recursive `rm` operand takes, through the same one `realpath`
(and, on Windows, the one `cygpath`). So a call with none of them keeps its k, and a move or content
destroyer with a payload cwd has the k a recursive `rm` has (4 in the #9752 census: `git`, `realpath`
and two `timeout`); a `Set-Content` of one file, or a `dd` with no `of=` or one naming `/dev/null`,
has nothing to judge and keeps its k. The Bash prefilter now also passes a command whose text holds
`mv`, `truncate`, `shred` or `of=` (as do the in-process checks on a substitution body, interpreter
code and a `parallel` item), and the PowerShell prefilter one holding `move`, `mv`,
`Clear-Content` or `Set-Content`, or `mi` or `clc` as a word, so such a call pays the tokenizer parse
(Bash) or the statement walk (PowerShell). `mv` and `Set-Content` are common commands, so more calls
pay that parse than under the earlier arms, and every `mv` from a repository pays the recursive-`rm`
judgment. Measured on melo-lap-001 (Windows 11 build 26300 on AC, Git Bash 5.3.15, Node 24.21.0)
with the method of the #9754 entry, guardrails at `480308656` against `c210da2bb` (the parent of
`0e920fea1`, the #9756 change; the only hook or lib difference from `b76fecf22` is
`--skip-unless-marker`, which this row does not pass), so one run times the #9756 through #9767
arms together; the head arm also holds #11347 (`block-cross-domain.sh`) and #11507 (an
allowed-roots fix), both in this row. The host was busier than in the #9754 run: the harness's S
was 24 to 26 ms and hyperfine's `bash -c :` floor 93 ms. Fan-out harness, 15 interleaved rounds of `--runs 7`, S = 20 ms
for the conversions below: the `Bash` row's paired median moved +17 ms and the `$(…)` sample −14 ms,
inside the +1 and +18 ms the untouched `Write` and `Edit` rows moved, so the common call shows no
change outside noise and keeps its k. With `hyperfine -N` (300 runs per arm per payload in five
alternating blocks), the `rm -rf ./build` control went from 558.1 to 533.7 ms and `mv ./a ./b` from
213.4 to 529.1 ms: +316 ms, about 16 S, which is what a recursive `rm` pays. That is overage against
the row's k × S, held as guardrails spawn-reduction work under the hook-budget contract's Rule 2
(the budget does not relax to absorb it).

**block-root-delete-target PowerShell indirection and pipelines (#9765).** The arm starts no process
of its own: the text `Invoke-Expression`, `pwsh -Command` or `Start-Process` runs goes through the
same in-process statement walk, an `-EncodedCommand` is decoded with bash builtins, and a pipeline's
listing and a .NET delete's path argument are read from words that walk already makes. Each path it
judges takes the path a recursive `Remove-Item` operand takes, so with a payload cwd the call has the
k a recursive `rm` has (4 in the #9752 census: `git`, `realpath` and two `timeout`), and a refusal
that names no target (an `-EncodedCommand` it cannot decode, a removal fed by no listing) starts no
process. The PowerShell prefilter now also passes a command whose text holds `pwsh` or `powershell`,
so such a call pays the statement walk; one with no delete ends there with no target to judge, and
every other call keeps its k. In the #9767 entry's run, the common call shows no change outside
noise, and `[IO.Directory]::Delete('build', $true)` went from 236.4 to 509.7 ms: +273 ms, about
14 S, the cost of the recursive-`rm` judgment (control 533.7 ms).
`Get-ChildItem ./build | Remove-Item -Recurse -Force`, which the earlier arm refused without judging
a target, now passes at 477.9 ms against that refusal's 198.4 ms. That is overage against the row's k × S, held as
spawn-reduction work under Rule 2.

**block-root-delete-target decoder sinks (#9763).** The arm starts no process of its own: it reads
each command's argv and redirections from the parse the guard already makes, and a program an
`eval`, a `-c` operand or a here-string hands a shell is parsed in-process as a `bash -c` operand is.
A decoder sink is refused before any target is judged, so its refusal adds no process to the row's k
(no `git`, `realpath` or `timeout`). The Bash prefilter now also passes a command whose text holds `base64`, `base32`, `basenc` or
`xxd`, and the PowerShell prefilter one whose text holds `FromBase64`, so such a call pays the
tokenizer parse (Bash) or the statement walk (PowerShell); one with no decoder sink and no delete ends
there with no target to judge, and every other call keeps its k. In the #9767 entry's run, the common
call shows no change outside noise, and `echo cm0gLXJmIC8= | base64 -d > build/rdt-x.sh` (a decoder
that passes the prefilter and is judged, with no sink) went from 188.2 to 188.1 ms: the decoder arm
adds no measurable cost.

**block-root-delete-target interpreter deletes (#9762).** The arm starts no process of its own: it
reads the interpreter's argv from the parse the guard already makes, lexes the program and finds its
deleter and command calls with bash builtins, and cuts a heredoc body out of the command by the byte
offsets the parse already reports. Each literal path it judges takes the path a recursive `rm`
operand takes, through the same one `realpath` (and, on Windows, the one `cygpath`), and a command the
code runs is parsed in-process as a `bash -c` operand is. So a call with no interpreter delete keeps
its k, an interpreter delete with a literal path has the k a recursive `rm` has (4 in the #9752
census: `git`, `realpath` and two `timeout`), and one refused because its path cannot be placed starts
no process. The Bash prefilter now also passes a command whose text holds `remove` or `.delete`, so
such a call pays the tokenizer parse; one with no interpreter delete ends there with no target to judge. Every
PowerShell call takes the same path as before. In the #9767 entry's run, the common call shows no
change outside noise, and `python3 -c "import shutil; shutil.rmtree('./build')"` went from 190.9 to
487.9 ms: +297 ms, about 15 S, the cost of the recursive-`rm` judgment (control 533.7 ms). That is
overage against the row's k × S, held as spawn-reduction work under Rule 2.

**block-root-delete-target git worktree remove (#9760).** The arm starts no process of its own: it
reads git's argv from the parse the guard already makes, matches the operand against the worktree
registry the protected-tree arm already reads with bash builtins, and each judged worktree takes the
path a recursive `rm` operand takes, through the same one `realpath` (and, on Windows, the one
`cygpath`). So a call with no forced `git worktree remove` keeps its k, and a forced one has the k a
recursive `rm` has (4 in the #9752 census: `git`, `realpath` and two `timeout`). The Bash prefilter
now also passes a command whose text holds `worktree`, so such a call pays the tokenizer parse; one
that is not a forced `git worktree remove` ends there with no target to judge. Every PowerShell call
takes the same path as before. In the #9767 entry's run, the common call shows no change outside
noise, and `git worktree remove --force ./wt` went from 202.8 to 465.9 ms: +263 ms, about 13 S, the
cost of the recursive-`rm` judgment (control 533.7 ms). That is overage against the row's k × S, held
as spawn-reduction work under Rule 2.

**block-root-delete-target robocopy deletes (#9758).** The arm starts no process of its own: it
reads robocopy's argv from the parse the guard already makes, and each judged destination or source
takes the path a recursive `rm` operand takes, through the same one `realpath` (and, on Windows, the
one `cygpath`). So a call with no robocopy delete keeps its k, and a robocopy delete has the k a
recursive `rm` has (4 in the #9752 census: `git`, `realpath` and two `timeout`). Both prefilters now
also pass a command whose text holds `robocopy`, so a robocopy call pays the tokenizer parse (Bash)
or the statement walk (PowerShell); one without `/MIR`, `/PURGE`, `/MOVE` or `/MOV` ends there with
no target to judge. In the #9767 entry's run, the common call shows no change outside noise, and
`robocopy src build /MIR` from the PowerShell tool went from 187.1 to 503.6 ms: +316 ms, about 16 S,
the cost of the recursive-`rm` judgment (control 533.7 ms). That is overage against the row's k × S,
held as spawn-reduction work under Rule 2.

**block-root-delete-target rsync deletes (#9756).** The arm starts no process of its own: it reads
rsync's argv from the parse the guard already makes, and each judged destination or source takes
the path a recursive `rm` operand takes, through the same one `realpath` (and, on Windows, the one
`cygpath`). The Bash prefilter now also passes a command whose text holds `rsync`, so an rsync
call pays the tokenizer parse; one without a deleting option ends there with no target to judge.
Every other Bash call, and every PowerShell call, takes the same path as before. In the #9767 entry's
run, the common call shows no change outside noise, and `rsync -a --delete ./src/ ./build/` went
from 231.9 to 508.3 ms: +276 ms, about 14 S, the cost of the recursive-`rm` judgment (control
533.7 ms). That is overage against the row's k × S, held as spawn-reduction work under Rule 2.

**block-root-delete-target pipeline-fed deletes (#9754).** The arm starts no process of its own,
and the prefilter is unchanged, because every `xargs` or `parallel` delete it judges holds `rm`,
`-delete` or `unlink`; so the row's k is unchanged. Each command of a call that passes the prefilter
now has its pipe feed recorded with bash builtins before it is judged, and an `xargs` or `parallel`
delete fed by a confined listing pays the recursive-delete judgment a recursive `rm` already pays,
through the same one `realpath` (and, on Windows, the one `cygpath`). Measured on melo-lap-001
(Windows 11 on AC, Git Bash 5.3.15, Node 24.21.0), guardrails at `b76fecf22` against `a1b88a685`
(the parent of `c3d7eb88d`, the #9754 change; no hook or lib code differs between `c3d7eb88d` and
`b76fecf22`), with a guardrails-only config and no telemetry sink. With the dotfiles fan-out harness
(sha256 `e1bbebb9…`), 15 interleaved rounds of `--runs 7`, S = 20 ms: the `Bash` row's paired
median moved +2 ms (0.1 S) and the `$(…)` sample −1 ms, inside the ±2 ms the untouched `Write` and
`Edit` rows moved; the row's median is 163 ms on both. With `hyperfine -N` (300 runs per arm in five
alternating blocks; its own `bash -c :` floor is 62 ms, a cold start where the harness times a fork
from bash), the row's median on `git status --short` went from 133.0 to 133.5 ms, on
`find ./build -type f | xargs rm -rf` from 143.5 to 365.1 ms, and on `rm -rf ./build` from 357.6 to
361.0 ms. The common call stays inside its k × S budget. A pipe-fed delete is a new judged shape: it
costs +222 ms (about 11 S at the harness's S), the cost a recursive `rm` already pays. This run did
not count its processes. Taking that recursive-delete cost as the budget for a pipe-fed delete is a
judgment, not a k × S result.

**block-root-delete-target find deletes (#9752).** The arm starts no process of its own, so the
common call's k is unchanged: it reads find's argv from the parse the guard already makes, and
each start point takes the path a recursive `rm` operand takes, through the same one `realpath`
(and, on Windows, the one `cygpath`). The Bash prefilter now also passes a command whose text holds
`-delete` or `unlink`, and a find delete pays the whole recursive-delete judgment a recursive
`rm` already paid: the strace census of `find ./build -name x -delete` goes from 2 processes
(`node`, `bash`) to 6, adding `git`, `realpath` and two `timeout`, the same 6 `rm -rf ./build`
starts at both commits. Every other Bash call, and every PowerShell call, takes the same path as
before. Measured on a WSL2 host (Linux 6.18, bash 5.3.9, Node 24.21.0, 24 cores; the Windows
reference host was not re-measured), guardrails at `3d3b1b15d` against its parent, with no
telemetry sink: with the fan-out harness above, 21 interleaved rounds of `--runs 15`, the `Bash`
row's paired median moved +0 ms and the `$(…)` sample +2 ms, against +0 and +1 ms for the
untouched `Write` and `Edit` rows. With `hyperfine` (300 runs, S = 0.76 ms), the row's median on
`find ./build -name x -delete` went from 43.5 to 115.7 ms, and on `rm -rf ./build` stayed at
119.9 and 119.1 ms. The common call stays inside its k × S budget. A find delete is a new
judged shape: its k goes from 0 to 4 and it costs +72 ms (about 95 S), the cost a recursive `rm`
already pays. Taking that recursive-delete cost as the budget for a find delete is a judgment,
not a k × S result.

**block-root-delete-target protected trees (#9751).** The arm starts no process of its own, so
the row's k is unchanged: it reads the worktree registry from the files git keeps with bash
builtins, tests each target for a `.git` with a builtin file test, and adds the protected paths to the one
`realpath` (and, on Windows, the one `cygpath`) the outside-tree judgment already runs. Only a
recursive delete that judgment reaches pays for it; every other Bash and PowerShell call takes the
same path as before. Measured on melo-lap-001 (Windows 11, Git Bash 5.3.15, Node 24.21.0) with
the dotfiles fan-out harness (sha256 `e1bbebb9…`), 15 interleaved rounds of `--runs 7`, guardrails
at `f39428d89` against its parent: the `Bash` row's paired median moved +1 ms (0.0 S, S = 21 ms),
the `$(…)` sample −3 ms, inside the ±6 ms (0.3 S) the untouched `Write` and `Edit` rows moved. The
harness samples are not recursive deletes, so this is the common call's cost. With k unchanged
and no measurable added work, the row stays inside its k × S budget.

**block-cross-domain (#9743).** The guard runs last on the Bash/PowerShell row and
starts no process on the common call (k = 0): with no map, which is every host that
has not written one, it exits after one file test, and with a map it reads the
compiled cache back with builtins. A call after the map changes starts two, `jq` to
compile it and `mv` to put the cache in place. A map `jq` rejects is cached the same
way, and while it stays malformed each call also pays the shared notice latch: three
process creations, one of them a `find`. A `jq` that exits non-zero is not cached and
runs again on the next call. A command that names no root or marker is not parsed.
`block-cross-domain.test.sh` pins the counts with the strace census
`block-dangerous-git.test.sh` uses, on hosts where strace runs. Measured on the same
host and harness as the entry above, 15 interleaved rounds of `--runs 7` at guardrails
0.61.2, against `block_cross_domain_enabled=false`: the `Bash` row's paired median
moved +0 ms (0.0 S, S = 21 ms) with no map and +5 ms (0.2 S) with a placeholder map
(the `$(…)` sample −6 ms and +5 ms), inside the ±6 ms (0.3 S) the untouched `Write`
and `Edit` rows moved. The map arm wrote the compiled cache and the disabled arm did
not, in every round. At k = 0 with no measurable added work, the row stays inside its
k × S budget.

**block-cross-domain deny (#9744).** A denied call starts no process either: the deny
document is built with builtins, and the owner directories come from the same `jq` run
that compiles the map, so k stays 0 and the strace census pins 0 creations for a call
that names another domain's root. A map with owners gives each call more paths to test:
two per owner, each in up to twelve spellings, the same count a root below `HOME` has.
Measured on the WSL2 host of the find-delete entry, guardrails at the #10870 merge against its parent,
with a placeholder map holding the cwd's domain and one other: with the fan-out harness, 21
interleaved rounds of `--runs 15`, the `Bash` row's paired median moved +1 ms and the `$(…)`
sample +1 ms, against +0 ms for the untouched `Write` and `Edit` rows. With `hyperfine` (300
runs, S = 0.76 ms), the row's median on `cat /x/b/notes.txt`, which the new code denies, went
from 43.0 to 44.9 ms (+1.9 ms, 2.5 S), at k = 0 on both sides of the census. The added work is
builtins only, inside the k × S plus measured-work budget.

**block-cross-domain identity positions (#9746).** k stays 0: the strace census of a denied
`git config user.email <other domain's marker>` counts `node` and `bash` alone, and the markers
come from the same `jq` run that compiles the map. Only a command whose prefilter named a marker
is checked for identity positions. Measured as the #9744 entry, guardrails at `1f9718c1d`
against its parent: the harness's `Bash` row and `$(…)` sample moved +0 ms, as did the `Write`
and `Edit` rows, and `hyperfine` put the denied `git config` call at 44.7 ms before and 45.9 ms
after (+1.2 ms, 1.6 S), inside the same budget.

**block-cross-domain config directories (#9747).** k stays 0: a domain's `gh` and `az`
directories come from the same `jq` run that compiles the map, and the check reads the
command's assignments and the hook's own environment with builtins, so the strace census
pins 0 creations for a denied `gh` call. From a `cwd` in a domain of a map with either
directory, a command whose text holds the word `gh` or `az` is parsed even when it names
no path or marker; every other command takes the same path as before. Measured on the WSL2
host of the #9744 entry (bash 5.3.9, Node 24.21.0), guardrails at `015c415c2` against its
parent, the row fired as `hooks.json` registers it with a placeholder map whose cwd domain
has both directories, and with no map: five runs of 30 interleaved rounds per tool, S = 1.0 ms.
The paired per-run medians moved −0.4 to +2.3 ms on the benign call (`git status --short`,
`Get-ChildItem -Force`), +0.1 to +1.4 ms on a denied `gh pr list` or `az account show`, and
up to +2.4 ms on an allowed `gh` that sets `GH_CONFIG_DIR` in a PowerShell statement; with
no map every arm stayed within −1.5 to +1.6 ms. With `hyperfine -N` (300 runs per arm in
five alternating blocks, S = 0.74 ms), the mapped row's median went from 43.4 to 43.5 ms on
`git status --short` and from 43.0 to 43.1 ms on the denied `gh pr list`. The census counts
`node` and `bash` alone on every arm at both commits. The added work is builtins only, at most
+2.4 ms (2.4 S), inside the k × S plus measured-work budget; the S multiples do not carry to
the Windows hosts, where builtin work does not scale with S.

**block-cross-domain identity writes (#9748).** k stays 0. With no map a call no longer
leaves after the file test: it takes the command from the dispatcher's primed fields and
tests it for `git` and `config` with builtins, and only a command holding both, or the
name of a listed identity file, is parsed, through the parse the dispatcher shares with
the row's other guards. With a map, the identity files come from the same `jq` run that
compiles it; the cache format moved to 4, so each map is compiled once more after the
update. The strace census pins 0 creations for a denied identity write, with a map and
without one. Measured on the WSL2 host of the find-delete entry (Node 24.21.0, bash 5.3.9,
load average 5 to 12 on 24 cores), guardrails at `53badc14e` against its parent
`62f5db9d3`, with no telemetry sink: the row fired as `hooks.json` registers it, timed with
`EPOCHREALTIME` beside a `bash -c :` floor (S median 1.0 ms), arm order rotated, five runs
of 30 rounds per payload, each map compiled before timing. An `strace` count of every arm
is 2 execs (`node`, `bash`) at both commits, and the write is denied after and allowed
before. Per-run paired median, after minus before:

| Payload (Bash; PowerShell) | No map | Placeholder map |
| --- | --- | --- |
| `git status --short`; `Get-ChildItem -Force` | −0.6 to +0.4 ms; −0.7 to +1.3 ms | −0.2 to +0.9 ms; −1.5 to +0.8 ms |
| `git config --get user.name` | +0.8 to +1.6 ms; +0.5 to +1.9 ms | +0.1 to +1.7 ms; +0.6 to +1.4 ms |
| `git config --global user.email …` (denied) | +1.0 to +2.7 ms; +0.6 to +1.9 ms | +0.6 to +1.9 ms; +0.9 to +1.3 ms |

The common call is unchanged, inside the 6 to 11 ms p10 to p90 spread of each arm. A
command holding `git` and `config` pays the parse, up to +2.7 ms (2.7 S on this host), at
k = 0: builtin work, inside the k × S plus measured-work budget, as the #9744 entry read
its +1.9 ms. The map's one recompile to format 4 was not timed. Builtin work does not scale
with S, so these S multiples do not predict the Windows cost.

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
cannot), and the seven telemetry-subject captures. Every decision is
byte-identical to 0.33.11 in exit code, stdout and stderr, over the perf
baseline's 17-command corpus in both tool modes (34 cases) and over every
command harvested from the eight guard suites.

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
0 immediately on Bash, so those parses were wasted work. After: the dispatcher skips
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
matcher, because an MCP matcher on the existing row
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

- **Telemetry still costs a sink dispatch, but only on the string-field guards.**
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
- **Per-guard classification work.** `block-dangerous-git` and `block-no-verify`
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

Per [`docs/contracts/hook-budget/README.md`](../../docs/contracts/hook-budget/README.md)
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

**The measurement that holds is the hook's own cost, ≈ 6.3 spawn-equivalents,
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
the way to replace this bound with a number, and is the follow-up to do.

**Share of the budget, and the overage.** The convention's ceiling is
≤ 1 s typical / ≤ 2 s worst-case **per tool call, counting `PreToolUse` and
`PostToolUse` together for one matcher**, so the set of hooks sharing that budget
is larger than the table above measures: guardrails also runs three `PostToolUse`
verifiers on `Write|Edit`, and the fleet's binding accounting for the whole
per-`Write` set is **≈ 1.9 s** (two formatters plus three guardrails verifiers),
already over the typical ceiling before this change and deeper into overage than
the PreToolUse-only slice measured here suggests. Against that set the
guard's own **≈ 505 ms is ≈ 25% of the ≤ 2 s worst-case ceiling as an upper
bound on its contribution**, and less than that in practice because it is
dispatched in parallel rather than added. Per the convention's rule 2 the budget
does not relax to absorb the overage: remediation is guardrails' own
spawn-reduction work (#1403), and this change offsets part of the spawn cost it adds: it removes
the `printf | tr` fork-and-exec pair from the shared normalizer and stops
resolving the telemetry subject in a subshell when no sink is wired, both costs
the pre-existing per-Bash-call lane was paying on every call. Operators who
cannot afford the addition have the per-hook kill switch below.

## Per-hook kill switches

Each guard is toggled by its own `userConfig` boolean, default **on**, except the two
behavioral-class advisories `workflow-resilience-check` and `flag-commit-pr-skill-bypass`, which
have been default **off** since 0.20.0 per #2021, and `block-credential-read`, default
**off** because its measured precision is below the bar
([guard precision](../../docs/contracts/hook-precision/guard-precision.md)). Set a switch to `true` to opt in, or to `false`
for a clean no-op. Each per-hook switch
disables one guard without touching the others. The [git hooks](#git-hooks) run without
Claude Code, so they have no switch here: a clone turns one off by declining its entry.

| Guard | Option |
| ----- | ------ |
| secret-pattern-detection | `secret_pattern_detection_enabled`, `secret_pattern_detection_allowed_roots`, `secret_pattern_detection_skip_gitignored` |
| hardcoded-path-check | `hardcoded_path_check_enabled` |
| block-no-verify | `block_no_verify_enabled` |
| block-dangerous-git | `block_dangerous_git_enabled` |
| block-windows-drive-tmp | `block_windows_drive_tmp_enabled` |
| block-exported-msys-pathconv | `block_exported_msys_pathconv_enabled` |
| block-root-delete-target | `block_root_delete_target_enabled`, `block_root_delete_target_allowed_roots`, `block_root_delete_target_protected_trees` |
| block-cd-prefix | `block_cd_prefix_enabled` |
| block-credential-read | `block_credential_read_enabled` |
| block-cross-domain | `block_cross_domain_enabled` |
| block-unresolved-pr-merge | `block_unresolved_pr_merge_enabled` |
| block-fix-request-post | `block_fix_request_post_enabled` |
| block-noncanonical-commit | `block_noncanonical_commit_enabled` |
| block-convention-violation | `block_convention_gate_enabled` |
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
  whatever arrived, rather than let an unscanned tool call through; the same
  holds for text that is not JSON. The one allowed shape is a well-formed JSON
  prefix on a pipe that then **closes**. That is the harness's payload cut
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
  and lies outside the temp tree.
- **Gitignore is the allowlist.** `hardcoded-path-check` skips any file
  `git check-ignore` matches against your `$CLAUDE_PROJECT_DIR`. Put
  machine-local files (`settings.local.json`, `.venv/`, …) in your
  `.gitignore` and they are exempt automatically. (Applies within an active
  project; with none, the hook already skips per the scoping rule above.)
- **Secret allowlist.** A generic built-in allowlist exempts dependency caches
  (`.venv/`, `node_modules/`), `.env.example` / `.sample` / `.template`
  placeholders, `tests/fixtures` / `tests/testdata` trees, `settings.local.json`,
  `CLAUDE.local.md`, and hook scripts. Two opt-in options exempt your own local
  notes: `secret_pattern_detection_allowed_roots` and
  `secret_pattern_detection_skip_gitignored` (see [Option details](#option-details)).
- **CLI-flag tuning.** `cli-flag-verify` checks a default binary set
  (`claude gh dotnet docker kubectl terraform az aws`); override with the
  `CLAUDE_PLUGIN_OPTION_CLI_FLAG_VERIFY_BINS` environment variable (`bin1,bin2,…`) in the
  committing environment and skip binaries with `CLAUDE_PLUGIN_OPTION_CLI_FLAG_VERIFY_SKIP_BINS`.
  `npm` is **excluded by default**, alongside
  `git` and `npx`, because every npm config key is a flag on every subcommand
  (`npm <command> --key=value`), so per-subcommand `--help` is non-exhaustive by
  design and the authoritative list (`npm config ls -l`) prints `prefix = "…"`
  rather than `--prefix`. A generic `--help` parser cannot consume it, and
  verifying against one produces false "unknown flag" findings. Re-add it with
  `CLAUDE_PLUGIN_OPTION_CLI_FLAG_VERIFY_BINS` if your project wants it checked anyway.
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

Every guard emits one structured [hook-telemetry](../../docs/contracts/hook-telemetry/README.md)
envelope per run to whatever `HOOK_TELEMETRY_SINK` names, carrying `status`
(`blocked` on a guard block, `ok` otherwise), `duration_ms`, and a privacy-safe
`data` payload (category **labels** only, never a secret value, matched path,
or full command). With `HOOK_TELEMETRY_SINK` unset, emission is a no-op and the
guards behave exactly as before.

## Requirements

- **bash 5.0+** and **jq**, the guards' runtime. Without **jq**, the guards that
  block irreversible operations deny every Bash and PowerShell call, with one
  line naming jq per call, and the other guards skip their work after one
  notice per session, never a silent disable.
- **Node.js** on `PATH`. Every guard row starts through `hooks/exec-bash.mjs`, which finds bash
  and runs the guard; the script declares no minimum Node version. The exec-form row needs `node`
  resolvable on `PATH`. Every `PreToolUse` guard row except `Workflow` sets `"onFailure": "block"`,
  so on Claude Code 2.1.295 or later a row that cannot start, because `node` or bash is missing, or
  that times out, denies the call. An older client ignores the key, and such a row enforces nothing
  ([hook budget](../../docs/contracts/hook-budget/README.md#which-rows-set-onfailure-block)).
  `/guardrails:check` reports a missing `node` or `jq`. A `SessionStart` row in shell form
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
check reports with guidance. `/guardrails:setup apply install-git-hooks` registers the
[git hooks](#git-hooks) (commit convention, secrets and paths, flags and references) for this
clone or, with `scope=shared`, for every clone.

## Configuration

### Option details

**`secret_pattern_detection_allowed_roots`.** For credentials you keep on purpose in local notes
that are never committed, such as a notes directory under home that is not a repository. Only you
set it. It is read from the hook's own environment, never from the tool call. A Write, Edit or
NotebookEdit that holds a token is not blocked when its target's real path is strictly under a
listed directory, so a symlink under a root that points outside it is still scanned and a path
outside whose real path lands under one is not. The root itself, a sibling that shares its name
prefix, a target spelled with a `.` or `..` segment, and an existing file with a second hard link
are scanned. On Windows only a drive-letter target (`C:/...`) is judged. An entry that is relative,
empty, UNC, holds a glob character, a line break or a `..` component, is not an existing directory,
or resolves to a filesystem root, a home directory (`HOME`, `USERPROFILE`) or a directory holding
one grants nothing. When neither `HOME` nor `USERPROFILE` is set, or a set one is relative or
missing, no entry grants. `~` is not expanded, so write each entry absolute. The option never
applies to a GitHub MCP write, whose content leaves the machine.

**`secret_pattern_detection_skip_gitignored`.** For a gitignored notes folder such as `.work/` in
each checkout and worktree, without listing every one. When `true`, a Write, Edit or NotebookEdit
that holds a token is not blocked when `git check-ignore` reports its target ignored by the
repository that holds the target, asked from the target's nearest existing directory, so it works
in a session started at home too. A tracked file, a file that is not ignored, a file in no
repository and a symlink are scanned, and so are an existing file with a second hard link and a
target spelled with a `.` or `..` segment. On Windows only a drive-letter target is judged. Anything
that can write `.git/info/exclude` or a `.gitignore` can make a path ignored without a tracked
diff. The option never applies to a GitHub MCP write.

Neither option changes the [`pre-commit-content`](#git-hooks) git hook: it still judges the lines a
commit adds, a force-added ignored file included. That backstop runs only in clones where
`/guardrails:setup apply install-git-hooks` ran, and a clone can decline it, so a file either
option exempts is checked at commit time only there.

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
cd) is left alone. With the same payload cwd, a protected tree is refused ahead of every root above,
the working tree included: a `.git`, and a directory holding one, so a throwaway clone under temp
too; the git toplevel itself; every worktree root git has registered for that repository (the
first 256, read from its `worktrees/*/gitdir` files); anything under `~/.claude`, so every delete
in a working tree there; Claude Code's temp tree, `<temp>/claude-<uid>` (`%TEMP%\claude` on
Windows) or the base the payload scratchpad sits in, where the base, a project or session
directory and another session's scratchpad are refused and this session's own scratchpad is
judged as before (inside a temp root that lies in that tree, only another session's scratchpad is
refused); and the trees in `block_root_delete_target_protected_trees`. A directory holding any of
them, or a glob whose matches do, is refused too. A glob is read as bash reads it with dotglob
off, unless the command names `dotglob`, `GLOBIGNORE` or `globdots`, and on the PowerShell tool,
whose `*` matches dot names. `.git` is matched in any case, and on Windows with a trailing dot or
space. A path named under a `.git`, the toplevel or a worktree root is not refused, and neither
is the toplevel's bash glob, which leaves its `.git` in place. Not seen: a repository nested below
the target other than those, a directory holding a `.git` that a glob in the last component
matches, and a glob option the shell had on before the command (a shell snapshot's `dotglob`). On the PowerShell tool the same target classes are refused for
`Remove-Item -Recurse` (and aliases `ri`/`rm`/`rd`/`rmdir`, with `-r`/`-rec` as unambiguous
prefixes) and for `cmd /c rd /s` / `rmdir /s`, without loading the shared PowerShell classifier.

**`block_root_delete_target_allowed_roots`.** The list ADDS TO the temp roots and the session
scratchpad the guard already allows. Only you set it, because it is read from the hook's own environment,
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

A **segment entry** has one `*` that is a whole path segment, followed by one literal name, for
example `D:/worktrees/*/.work` for the scratch each worktree keeps. It allows only a path strictly
under that name inside a direct child of the directory before the `*`
(`D:/worktrees/wt-a/.work/tmp`), and never one that is itself a symlink. It refuses the named directory itself
(`D:/worktrees/wt-a/.work`) and its glob, a sibling of it (`D:/worktrees/wt-a/src`), the same name
at any other depth (`D:/worktrees/wt-a/b/.work/tmp`), a one-level name or a target ending in a dot
or a space, which Windows trims (`.work/...` names `.work`), and a trailing-slash operand whose
target does not exist yet. The protected trees are judged first, so a `.git` or a worktree root
stays refused. The directory before the `*` follows the rules above. An entry whose `*` shares a segment with
other text (`D:/worktrees/wt-*/.work`) or that holds a second `*`, any other glob character, a name
of `.` or `..`, or more than one name after the `*` grants nothing.

**`block_root_delete_target_protected_trees`.** The list ADDS TO the protected trees the guard
already refuses, and wins over every allowed root, the working tree and the temp roots included.
A recursive delete of a listed directory, of anything under it, or of a directory holding it is
refused, and so is a glob whose matches reach one (`rm -rf /data/*` with `/data/keep` listed).
Like the allowed roots, only you set it: it is read from the hook's own environment, never from
the command text, and targets are compared by real path. An entry that is relative, empty, holds
a glob character, a line break or a `..` component, names a drive path on a host without drive
letters, or resolves to a filesystem root protects nothing; the rest of the list still applies.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `secret_pattern_detection_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_SECRET_PATTERN_DETECTION_ENABLED` | Blocks writes containing high-confidence secret or credential patterns. On by default. |
| `secret_pattern_detection_allowed_roots` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_SECRET_PATTERN_DETECTION_ALLOWED_ROOTS` | Comma-separated absolute directories; a Write, Edit or NotebookEdit whose real path is strictly under one is not scanned for secrets. Empty by default. A commit is still checked only in clones where /guardrails:setup apply install-git-hooks ran. Limits: README Option details. |
| `secret_pattern_detection_skip_gitignored` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_SECRET_PATTERN_DETECTION_SKIP_GITIGNORED` | When true, a Write, Edit or NotebookEdit to a file its own repository ignores is not scanned for secrets. Off by default. A commit is still checked only in clones where /guardrails:setup apply install-git-hooks ran. Limits: README Option details. |
| `hardcoded_path_check_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_HARDCODED_PATH_CHECK_ENABLED` | Blocks writes containing hardcoded machine-specific paths. On by default. |
| `block_no_verify_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BLOCK_NO_VERIFY_ENABLED` | Blocks git hook-bypass attempts: --no-verify, core.hooksPath=, and hook-manager env-var disables for a configurable set (lefthook, husky, pre-commit and simple-git-hooks by default). On by default. |
| `block_no_verify_hook_manager_prefixes` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_BLOCK_NO_VERIFY_HOOK_MANAGER_PREFIXES` | Comma-separated hook-manager env-var name prefixes block-no-verify treats as a bypass when set to 0 or false (e.g. lefthook,husky). Empty, the default, uses the built-in set: lefthook, husky, pre_commit, simple_git_hooks. |
| `block_dangerous_git_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ENABLED` | Blocks irreversible git operations: push --force, reset --hard, clean -f, worktree-wide checkout or restore discards, and a push --force-with-lease that leases against a value git resolves at push time. On by default. The README's Option details define the lease case. |
| `block_dangerous_git_allow` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW` | Comma-separated forms block-dangerous-git permits: push-force, push-lease-unsafe, reset-hard, clean-force, checkout-dot, restore-dot, checkout-force, plus the PowerShell ps-unparsable-* sink tokens the README's Option details list. Empty, the default, blocks all. |
| `block_credential_read_enabled` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_BLOCK_CREDENTIAL_READ_ENABLED` | Blocks a command whose output is a credential: git credential fill, gh auth token, a token-shaped variable echoed, and an interpreter (python -c, node -e) reading .env, .netrc, ~/.ssh/id_* or ~/.aws/credentials. cat is left to Read() deny rules. Off by default: precision below the bar. |
| `block_credential_read_allow` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_BLOCK_CREDENTIAL_READ_ALLOW` | Comma-separated families block-credential-read permits: credential-fill, gh-auth-token, env-echo, credential-file-read. Empty, the default, blocks all. |
| `block_cross_domain_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BLOCK_CROSS_DOMAIN_ENABLED` | Denies a Bash or PowerShell global git identity write (git config --global user.email and kin, a ~/.gitconfig write). In an identity domain (identity-domains.json) also denies naming another domain's path, using its marker, or gh/az without the domain's config dir. On by default. |
| `block_unresolved_pr_merge_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BLOCK_UNRESOLVED_PR_MERGE_ENABLED` | Blocks a pull-request merge (gh pr merge, REST, GraphQL or an MCP merge tool) while the PR has unresolved review threads, a changes-requested review, or failing checks. Fails open, visibly, when the PR state cannot be read. On by default. |
| `merge_guard_ignored_checks` | string | `"github-actions:merge"` | `CLAUDE_PLUGIN_OPTION_MERGE_GUARD_IGNORED_CHECKS` | Comma-separated <app slug>:<check name> pairs block-unresolved-pr-merge never judges as pending or failing. The default, github-actions:merge, is the pr-merge lane's own merge job, which runs as the merger rather than as a gate. Empty judges every check. |
| `block_fix_request_post_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BLOCK_FIX_REQUEST_POST_ENABLED` | Blocks an agent from posting the PR-fix lane fix request (a line starting "PR-fix lane: please fix this finding") to GitHub through gh, curl or a GitHub MCP write tool. Only the owner posts it, in the GitHub UI. On by default. |
| `block_windows_drive_tmp_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BLOCK_WINDOWS_DRIVE_TMP_ENABLED` | Blocks writes to a Windows drive-root temp path (/tmp, C:\tmp, \tmp, /c/tmp) that resolves to <drive>:\tmp instead of %TEMP%, in shell commands and Write/Edit file paths alike. On by default. The Git for Windows exception is in the README's Option details. |
| `block_exported_msys_pathconv_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BLOCK_EXPORTED_MSYS_PATHCONV_ENABLED` | Blocks a leaking MSYS path-conversion suppressor on Windows: an exported MSYS_NO_PATHCONV or MSYS2_ARG_CONV_EXCL, or one prefixed on a child shell (MSYS_NO_PATHCONV=1 bash -c ...). On by default. What it does not match is in the README's Option details. |
| `block_cd_prefix_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BLOCK_CD_PREFIX_ENABLED` | Denies a Bash command that opens with cd <path> followed by &&, ; or a newline and then runs git or writes to a relative path, with the reason to use git -C <abs path>. cd . and a cd to the current directory pass. On by default. |
| `block_root_delete_target_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BLOCK_ROOT_DELETE_TARGET_ENABLED` | Blocks a recursive delete (rm, Remove-Item, rd /s) of a filesystem, home, drive or UNC root, an empty or bare-variable operand, a protected tree (.git, repo or worktree root, ~/.claude, other sessions' scratchpads), or a path outside the repo, temp, the scratchpad and allowed roots. On by default. |
| `block_root_delete_target_allowed_roots` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_BLOCK_ROOT_DELETE_TARGET_ALLOWED_ROOTS` | Comma-separated absolute directories; a recursive delete passes when its real path is strictly under one. An entry like D:/worktrees/.tmp-* allows only direct children whose name extends that prefix. Empty by default; adds to the temp roots and scratchpad. Limits: README Option details. |
| `block_root_delete_target_protected_trees` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_BLOCK_ROOT_DELETE_TARGET_PROTECTED_TREES` | Comma-separated absolute directories a recursive delete never removes, even under the repo or an allowed root: the directory, anything under it, and a directory holding it are refused. Empty by default; adds to the built-in protected trees. Limits: README Option details. |
| `block_noncanonical_commit_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BLOCK_NONCANONICAL_COMMIT_ENABLED` | Blocks git commit -m when the message holds a $ or a backtick the shell would expand (single-quote it, or pipe it via -F -); a plain message passes, multi-line included. On by default. Exempt: --amend, -C/-c, --fixup/--squash, -F <path>, and an in-progress merge or rebase. |
| `block_noncanonical_commit_allow` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_BLOCK_NONCANONICAL_COMMIT_ALLOW` | Comma-separated form tokens block-noncanonical-commit permits. The only token today is message-flag, which permits a -m message the shell would expand. Empty, the default, permits none. |
| `block_convention_gate_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BLOCK_CONVENTION_GATE_ENABLED` | Blocks a commit subject or gh pr create --title that violates the team-tracked convention pattern in docs/conventions/source-control.yaml, or for one release in .claude/source-control.md. On by default; with no tracked pattern nothing is enforced. Same exemptions as block-noncanonical-commit. |
| `git_hooks_notice_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_GIT_HOOKS_NOTICE_ENABLED` | At session start, names /guardrails:setup apply install-git-hooks once when this clone lacks a guardrails git-hook entry or holds a drifted one; a declined entry stays quiet. Turning it off also silences the session-start notice that jq is missing. On by default. |
| `workflow_resilience_check_enabled` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_WORKFLOW_RESILIENCE_CHECK_ENABLED` | Advises on Workflow fan-out with no wave cap of its own; never blocks. Off by default since 0.20.0: a behavioral-class prose injector, config-disabled per the instruction-economy evidence gate (#2021). Set true to opt back in. |
| `flag_commit_pr_skill_bypass_enabled` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_FLAG_COMMIT_PR_SKILL_BYPASS_ENABLED` | Advises when a direct gh pr create bypasses the source-control pull-request skill; never blocks. Off by default since 0.20.0: a behavioral-class prose injector, config-disabled per the instruction-economy evidence gate (#2021). Set true to opt back in. |
| `stdin_read_timeout` | number<br>*min 1* | `2` | `CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT` | Idle bound on reading the hook payload from stdin: how long a silent pipe is tolerated before a blocking guard fails closed. Default 2. Only a JSON payload the pipe closed on mid-document is allowed with a notice; a stalled pipe stays a block. |

### How to set these

Three supported routes:

1. **Interactively.** Open this plugin's options dialog ([`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session)):
   `/plugin configure guardrails@<marketplace>`.
2. **Headless.** Save the values with [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure),
   run from the project the plugin is installed in. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin configure guardrails@<marketplace> --values-stdin < values.json
   ```

   `values.json` holds a JSON object of strings, booleans included:

   ```json
   {"secret_pattern_detection_enabled": "<value>"}
   ```

   This is the preferred headless route in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md), which records its
   limits: the Claude Code version it needs, which install it finds, how it rejects a bad
   value, and why a session started before the change keeps the old value until a fresh
   session starts. Do **not** `claude plugin uninstall` to reconfigure: see
   [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).

   The fallback the convention names, for a Claude Code release without
   `plugin configure`, reruns the install with the new value, passing the scope
   `claude plugin list` reports for this plugin:

   ```shell
   claude plugin install guardrails@<marketplace> -s <scope> --config secret_pattern_detection_enabled=<value>
   ```

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

   The [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs)
   entry names the settings scopes Claude Code reads this key from.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself; set the value through one
of the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure): the `--values-stdin` flag's reference entry
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
