### Assistant final message, turn 1

I've read the conventions file and the command. Here's the cause: `CommitCommand.Run()` (`src/Tarnquill.Cli/Commands/CommitCommand.cs:11-20`) always calls `Console.ReadLine()`, and it takes no arguments at all because `Program.cs:18` doesn't pass any. In CI, stdin is usually left open with nothing on it, so the first `ReadLine` never returns.

The [redacted] workflow has me show a plan and wait for your yes before changing anything, so here is the plan.

## Plan

**Interface**
```
tq commit                                   # unchanged: asks for type, then message
tq commit --type feat --message "add paging"    # no prompts (-t / -m short forms)
tq commit -t fix -m "..." --dry-run         # prints "fix: ..." and doesn't run git
tq commit --help
```
- **Both flags given:** no prompts. It goes straight to `git commit -m "<type>: <message>"` through the existing `ProcessRunner.Run`.
- **A flag is missing and stdin is a terminal:** it asks only for the missing value, using the same prompt text as today. Running bare `tq commit` at the keyboard works exactly as it does now.
- **A flag is missing and stdin is not a terminal** (`Console.IsInputRedirected`): it fails straight away instead of hanging, with a message like `tq commit: --type is required when stdin is not a terminal (one of feat/fix/docs/chore), e.g. tq commit --type fix --message "..."`.
- **Exit codes:** 0 ok; 1 when `git commit` fails; 2 for a missing flag, an unknown flag or a bad `--type` value. Answers typed at the prompt keep today's exit 1, so the keyboard path doesn't change.
- **`--json`:** not included, because the conventions file lists `--json` on `tq commit` under "Not yet". Basis: `docs/conventions[redacted].md` "Not yet".

**Files**
- `src/Tarnquill.Cli/Commands/CommitCommand.cs`: change it to `Run(string[] args)`, add hand-written flag parsing in the same style as `ItemCommentCommand`, and add `--help` and `--dry-run`. Basis: the project already parses arguments by hand and has no parser library.
- `src/Tarnquill.Cli/Program.cs`: pass `args[1..]` to the command and update the usage line.
- `docs/conventions[redacted].md`: in the Tools section, replace "No flags bypass the prompts" with the new flags and when it prompts.

**Check after writing:** `make build`, `make check`, then smoke runs: `tq commit --help`, a `--dry-run` with both flags, and `tq commit </dev/null` to confirm it fails at once with exit 2. I won't make a real commit unless you want one.

## One decision for you
**Piped answers.** Today `printf 'feat\nmsg\n' | tq commit` happens to work. With the plan above it would fail and point the caller to the flags. That's the rule that fixes your CI hang: never read prompts from stdin when it isn't a terminal. The options are:
- **(a)** Fail fast as planned.
- **(b)** Still read piped answers, and fail if stdin is empty or closed. This keeps pipe users working, but it can still hang when CI leaves stdin open, which is the bug you hit.

What would settle it is whether any of your scripts pipe answers into `tq commit` today. Nothing in this repo does, but I can't see your CI configs from here.

Shall I go ahead, and with (a) or (b)?

### Assistant final message, turn 2

`tq commit` now takes its type and message as flags, so your CI job won't hang.

**For CI:**
```
tq commit --type fix --message "handle empty pages"
```
The short forms are `-t` and `-m`. If a script leaves out either flag, the command exits 2 straight away with a message naming the missing flag, instead of waiting for input.

**At the keyboard:** running bare `tq commit` still asks for the type, then the message, with the same prompts and exit codes as before. If you give only one flag at a terminal, it asks only for the other.

**Also added:**
- `--dry-run` prints the commit it would make and doesn't run git.
- `--help` shows usage and examples.
- Exit codes: 0 committed, 1 when `git commit` fails or a typed answer is invalid, 2 for a missing or invalid flag.

**One behavior change:** I went with option (a) from the plan, since you approved it as written. Piping answers in, like `printf 'feat\nmsg\n' | tq commit`, no longer works; it fails and points to the flags instead. If any of your scripts do that, tell me and I'll switch to (b).

**Files changed:**
- `src/Tarnquill.Cli/Commands/CommitCommand.cs`: the flags, the terminal check, `--dry-run` and `--help`. Git still runs through `ProcessRunner.Run`.
- `src/Tarnquill.Cli/Program.cs`: passes the arguments to the command and has the new usage line.
- `docs/conventions[redacted].md`: the Tools entry for `tq commit` now lists the flags and when it prompts. It used to say "No flags bypass the prompts".
