### Assistant final message, turn 1

I've added flags so CI can run `tq commit` without anyone typing:

```sh
tq commit --type feat --message "add paging helper"
```

**I haven't built or run any of this.** This session couldn't use the shell, so please run `make build` and `make check` before relying on it.

**At the keyboard, nothing changes.** Plain `tq commit` still asks for the type and then the message. The wording, the checks, and the exit code 1 for a bad answer are all the same.

**In scripts and CI:**
- If both `--type` and `--message` are given, it skips the prompts and commits.
- If you give only one at a keyboard, it asks only for the missing one.
- If there's no keyboard attached (input is piped or redirected) and either flag is missing, it stops at once with exit code 2 and says to pass both flags. This is what stops the hang.
- A bad `--type` or an empty `--message` also exits with code 2.

**One behaviour change to know about:** feeding answers through a pipe, like `printf 'feat\nmsg\n' | tq commit`, used to work and now exits with code 2. I couldn't tell a pipe that has answers waiting from CI's pipe that never sends any, so I made it stop rather than risk the hang. If anyone relies on piping, they'll need to switch to the flags.

**Other options,** per the rules in `AGENTS.md` for new commands:
- `--help` shows usage and exits 0.
- `--dry-run` prints the commit message it would use and doesn't commit.
- `--json` prints the result as JSON. If it still has to ask a question, the question goes to the error output so the JSON stays clean.

**Files changed:**
- `src/Tarnquill.Cli/Commands/CommitCommand.cs`: the new flags and the stop-instead-of-wait logic.
- `src/Tarnquill.Cli/Program.cs`: passes the extra arguments through and updates the usage line.
- `AGENTS.md`: it said "No flags bypass the prompts", which is no longer true, so I updated the `tq commit` entry.

### Assistant final message, turn 2

I built it and tried the new options. `tq commit` no longer hangs when run from a script, which is the CI fix.

**Build:** `make build` succeeds with no warnings or errors.

**What I ran** (all with input disconnected, as in CI, and none of them committed anything):

| Command | Result |
|---|---|
| `tq commit` | exit 2: `no terminal to prompt on; pass --type and --message` |
| `tq commit --type nope --message x` | exit 2: `unknown change type 'nope' (expected feat/fix/docs/chore)` |
| `tq commit --type feat --message smoke --dry-run` | `Would commit: feat: smoke` |
| `tq commit --type fix --message x --dry-run --json` | `{"ok":true,"dryRun":true,"subject":"fix: x"}` |

**Not yet tried:**
- **A real commit using the flags.** I didn't want to put a test commit on `main`.
- **The keyboard prompts.** I can't type answers from here; that code is unchanged from before, so I expect it to behave the same.
- **The `--help`, empty-message and unknown-flag cases.** The tool wouldn't let me run them.

**`make check` fails, but not because of this change.** Two of the paging checks in `Tarnquill.Core` fail: `PageCount(10, 5)` returns 3 instead of 2, and `PageCount(0, 5)` returns 1 instead of 0. I didn't touch that code.

The changes are still uncommitted on `main`. Should I put them on a new branch and commit, or would you like to look at the diff first?
