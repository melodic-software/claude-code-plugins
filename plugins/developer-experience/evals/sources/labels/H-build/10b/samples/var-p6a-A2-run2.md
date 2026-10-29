### Assistant final message, turn 1

I haven't changed any files yet. This is the plan for your approval first.

**Why it hangs:** `tq commit` (`src/Tarnquill.Cli/Commands/CommitCommand.cs:11-20`) always asks for the type and message on the console. There's no flag to supply them, and in CI it sits waiting for an answer that never comes.

## Plan

**Files to change**
1. `src/Tarnquill.Cli/Commands/CommitCommand.cs`: add flag parsing, decide when to prompt, and add `--help` and `--dry-run`.
2. `src/Tarnquill.Cli/Program.cs`: pass the arguments to the command (`CommitCommand.Run(args[1..])`) and update the usage line.
3. `docs/conventions[redacted].md`: rewrite the `tq commit` entry under Tools, since "No flags bypass the prompts" will no longer be true.

**New usage**
```
tq commit                                   # unchanged: prompts for type, then message
tq commit --type fix --message "handle empty page"
tq commit -t feat -m "add paging" --dry-run # prints the git command, commits nothing
tq commit --no-input ...                    # never prompt, even at a keyboard
tq commit --help
```
- `--type, -t <feat|fix|docs|chore>`, `--message, -m <text>`, `--no-input`, `--dry-run`, `--help, -h`.
  - `-m` matches `git commit -m`. Basis: the repo wraps `git commit -m`.
- **When it prompts:** it only asks for values you didn't pass as flags, and only when input is a real keyboard (`!Console.IsInputRedirected`) and `--no-input` isn't set. Otherwise it stops at once with an error that names the missing flag and shows an example, e.g. `tq commit: --type is required when not run from a terminal (e.g. tq commit --type fix --message "…")`.
  - Basis: CLI contract rule 1 (clig.dev, .NET design guidance, `gh`, terraform).
- **Exit codes:**
  - 0: committed (or the dry-run succeeded).
  - 1: git failed. This also covers a bad answer at the prompt, which returns 1 today and will keep doing so.
  - 2: a usage error from flags (a missing or invalid value, or an unknown flag).
  - Basis: the "CLI contract" section of the conventions doc.
- **`--json`:** not added, because the conventions list it under "Not yet" for `tq commit`.
- **Helper:** git still runs through the existing `ProcessRunner.Run`, with no new helper and no new dependency. Arguments are parsed by hand, the same way `ItemCommentCommand` does it. Basis: repository.

**At the keyboard:** a bare `tq commit` asks the same two questions, in the same wording, with the same exit codes.

## Open question: piping answers into `tq commit`
Today `printf 'fix\nmsg\n' | tq commit` happens to work, because the prompts read from piped input. With the rule above, that would now stop with an error asking for `--type`/`--message`. The conventions don't document piping, so I can't tell from the repo whether anyone depends on it. The options:
- **(a) Fail fast whenever input isn't a keyboard.** The CLI contract's non-interactive rule calls for this, and it's the most reliable fix for the CI hang. It does break piping.
- **(b) Keep reading piped input, and stop prompting only when flags or `--no-input` are given.** Piping keeps working, but CI has to pass the flags, and any script that forgets them can still hang.
- **(c) Do (a), but first print a warning for one release** when it detects piped answers.

What would settle it: whether any script or person on the team pipes answers into `tq commit`.

## Verification
I'll run `make build` and `make check`, then `tq commit --help` and `tq commit -t fix -m test --dry-run`, then `tq commit </dev/null` to confirm it exits 2 at once instead of hanging. I won't make a real commit unless you agree. Right now shell commands are blocked in this session ("don't ask" mode), so I'll need Bash permission to run any of this. Without it, I'll mark the change as unverified. The Windows/pwsh path will also be unverified, since I'm on Linux.

Reply yes with (a), (b) or (c), and I'll make the change.

### Assistant final message, turn 2

Before I write anything I need one answer from you: what should happen when answers are piped into `tq commit` (e.g. `printf 'fix\nmsg\n' | tq commit`)? Every option leaves typing at the keyboard exactly as it is today. They differ only for scripts:

- **(a) Fail at once with an error naming `--type`/`--message`.** CI can never hang, but anyone who pipes answers today breaks.
- **(b) Keep reading piped answers.** Only the new flags or `--no-input` skip the prompts. Nothing existing breaks, but a script that leaves out the flags can still hang.
- **(c) Like (a), but warn for one release first** before switching to failing.

I'm not picking one for you because it turns on something the repo doesn't show: whether any script or person on the team pipes answers into `tq commit`. If you know nobody does, (a) is the simple choice. If you're not sure, (b) or (c) is safer.

Also, shell commands are still blocked in this session. Allow Bash if you want me to build and run the commands once the change is in; otherwise I'll report it as unverified.

No change has been made yet, so there is no smoke result: `tq commit` has not been built or run.
