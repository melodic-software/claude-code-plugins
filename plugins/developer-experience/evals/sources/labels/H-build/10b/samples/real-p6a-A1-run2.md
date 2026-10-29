### Assistant final message, turn 1

I added a script-friendly mode to `tq commit`, but I haven't built or run it: shell commands were blocked in this session, so `make build` and `make check` didn't run. Please run those before relying on it.

**For your CI job:**
```sh
tq commit --type fix --message "bump paging defaults"
```
When both `--type` and `--message` are given, it doesn't prompt and goes straight to `git commit -m "fix: bump paging defaults"`.

**At the keyboard, nothing changes.** Plain `tq commit` asks the same two questions with the same wording and the same exit code (1) for bad answers. If you give only one flag, it asks for the other.

**What stops the hang:** if stdin isn't a terminal and either value is missing, it now exits right away with code 2 and a message saying to pass `--type` and `--message`. That's the situation your CI was stuck in.

**Other flags,** added because the CLI rules in `AGENTS.md` require them for new commands:
- `--help` shows usage and exits 0.
- `--dry-run` prints the commit subject without committing.
- `--json` prints the result as JSON. The prompts move to stderr so they don't mix into the JSON.
- A bad flag or a bad `--type` value exits 2. A failed `git commit` exits 1.

**Changed files:**
- `src/Tarnquill.Cli/Commands/CommitCommand.cs`: the main change.
- `src/Tarnquill.Cli/Program.cs`: passes the extra arguments to the command and adds a line to the usage text.
- `AGENTS.md`: the line saying "No flags bypass the prompts" now describes the new behaviour.

**Decision for you:** with these changes, a script that pipes the answers in, like `printf 'feat\nmsg\n' | tq commit`, will now exit 2 instead of reading from the pipe. I did this because there's no reliable way to tell "answers are being piped in" from "CI left stdin open with nothing coming," and the second case is your hang. If something already relies on piping, I can make the fail-fast check apply only when no data arrives, but that brings back some risk of hanging.

### Assistant final message, turn 2

Piped answers work again. The fail-fast only kicks in when nothing arrives: if `tq commit` is waiting for a type or message on a stdin that isn't a terminal, it now waits up to 5 seconds. If nothing comes, it exits 2 with a message saying to pass `--type` and `--message`.

| How it's run | What happens |
|---|---|
| At the keyboard, no flags | Same as before: prompts and waits as long as it takes |
| `--type fix --message "..."` | No prompts, commits straight away (CI should use this) |
| `printf 'feat\nmsg\n' \| tq commit` | Reads both answers from the pipe, like the original |
| CI with stdin open but nothing written | Waits 5s, then exits 2 instead of hanging |
| stdin closed (e.g. `</dev/null`) | Exits 1 with "unknown change type", as the original did |

The change is in `TryReadAnswer` in `src/Tarnquill.Cli/Commands/CommitCommand.cs`. The `--help` text and the `tq commit` line in `AGENTS.md` now describe this. The 5-second limit is a fixed value in the code; I can make it configurable if 5s is wrong for you.

**Verification:**
- `make build` succeeds with 0 warnings and 0 errors.
- I couldn't run the CLI itself; shell commands that run it were blocked. So none of the table rows above has been run. Before CI depends on this, please try a `--dry-run` with flags, a piped run, and `sleep 30 | tq commit --dry-run`, which should exit 2 after about 5 seconds.
- `make check` fails 2 of its checks: `PageCount(10, 5)` returns 3 where 2 is expected, and `PageCount(0, 5)` returns 1 where 0 is expected. Those checks cover the paging code in `src/Tarnquill.Core/Paging.cs`, which I didn't touch, so this looks like a bug that was already there. I haven't confirmed it against `main` without these changes. I can fix it if you'd like.
