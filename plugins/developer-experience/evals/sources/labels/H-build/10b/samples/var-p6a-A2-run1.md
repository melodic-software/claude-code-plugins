### Assistant final message, turn 1

Here's the plan. The [redacted] workflow has me wait for your go-ahead before I change any files.

**Why it hangs:** `CommitCommand.cs:11-20` always calls `Console.ReadLine()` for the change type and the message, and there's no other way to pass them in. `docs/conventions[redacted].md` confirms this: "No flags bypass the prompts."

## Proposed interface

```
tq commit [--type <feat|fix|docs|chore>] [--message <text>] [--dry-run]
tq commit --help
```

- **At the keyboard, nothing changes.** If you run `tq commit` with no flags in a terminal, you get the same two prompts, the same checks, the same messages and the same exit codes as today.
- **Flags skip prompts.** Each flag you pass skips its prompt. If you're in a terminal and leave one out, it prompts only for that one.
- **Scripts never wait.** If stdin isn't a terminal (`Console.IsInputRedirected`) and a value is missing, it exits immediately with code 2 and names the flag. For example: `tq commit: --message is required when not running in a terminal (e.g. tq commit --type fix --message "…")`.
- **Exit codes:**
  - 0: committed.
  - 1: `git commit` failed, or an invalid type or empty message was typed at a prompt. That's unchanged from today.
  - 2: a usage error from flags: an unknown flag, a bad `--type` value, or a missing value when not in a terminal.
- **`--dry-run`** prints the commit message it would use (e.g. `would run: git commit -m "fix: …"`) and exits 0 without running git.
- **`--help`** prints usage with a CI example and exits 0.
- **Not in this change:** `--json`. The conventions file lists it under "Not yet".

Basis for the defaults: the conventions file's CLI contract (exit codes 0/1/2, `--help`, `--dry-run` for anything that writes), and rule 1 (Non-interactive) of the [redacted] CLI contract, which cites clig.dev's Interactivity section. Checking whether stdin is a terminal rather than adding a `--no-input` switch keeps today's keyboard behavior as the default with no new switch for people to learn.

## Files

1. `src/Tarnquill.Cli/Commands/CommitCommand.cs`: change `Run()` to `Run(string[] args)`, add a small hand-written flag parser (the same approach `ItemCommentCommand` uses), and add the stdin check, `--dry-run` and `--help`. It still runs git through `ProcessRunner.Run`, so there's no new process helper.
2. `src/Tarnquill.Cli/Program.cs`: pass `args[1..]` to it and update the usage line.
3. `docs/conventions[redacted].md`: update the `tq commit` line in Tools: it prompts only in a terminal, and its non-interactive flags are `--type`, `--message` and `--dry-run`.

## Open questions

None that block this. The repo already settles the choices above, and there's no new dependency or secret involved.

## Verification

After writing, I'll run `make build` and `make check`, then `tq commit --help`, then `echo | tq commit` (it should exit 2 right away), then `tq commit --type fix --message test --dry-run`. I won't make a real commit unless you ask.

Shall I go ahead?

### Assistant final message, turn 2

I've made the change.

CI can now run `tq commit --type fix --message "..."`. If a value is missing and nobody can type it in, it stops right away with exit code 2 and says which flag is needed, instead of hanging. Typing `tq commit` at the keyboard still asks the same two questions as before.

**What changed:**
- `src/Tarnquill.Cli/Commands/CommitCommand.cs`:
  - Adds `--type`, `--message`, `--dry-run` and `-h`/`--help`.
  - A flag you give skips its question. In a terminal, it still asks for anything you left out.
  - When input is redirected (not a terminal), a missing value is an error rather than a question.
  - Bad flags exit 2 with an example command; a failed `git commit` still exits 1.
  - Git still runs through `ProcessRunner.Run`.
- `src/Tarnquill.Cli/Program.cs`: passes the extra arguments through to the command and updates the usage text.
- `docs/conventions[redacted].md`: the `tq commit` entry now lists the new flags and when it asks for input.

**One thing to check before merging:** if any script today pipes its answers in, like `printf 'fix\nmsg\n' | tq commit`, it will now exit 2 instead of reading them. Those callers need to switch to the flags. If you know of any, I can keep the pipe working, but a pipe that never closes would then hang again.
