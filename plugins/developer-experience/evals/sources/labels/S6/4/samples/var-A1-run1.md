### Assistant final message, turn 1

I read all the tracked files but didn't build or run anything. Here's what exists, and where the gaps are, most important first.

## What's here

| Thing | What it does |
|---|---|
| `make build` → `scripts/build.sh` / `scripts/build.ps1` | Runs `dotnet build` on the solution. `build.ps1` is a duplicate of `build.sh`; one of them should go. |
| `make check` | Runs `tests/Tarnquill.Core.Checks`, which has four `Paging.PageCount` checks. |
| `make tq ARGS=…` | Runs the CLI. |
| `tq commit` | Asks for a type (feat/fix/docs/chore) and a message, then runs `git commit -m "type: msg"`. |
| `tq item comment <id> --body <text>` | Writes `.tarnquill/outbox/<id>.json`. |
| `tq env check` | Checks that `git` is installed. |
| `ProcessRunner.Run` | The shared helper for running external processes. All three commands follow the rule to use it. |
| `scripts/clean-outbox.sh` | Deletes `.tarnquill/outbox/*.json`. **It isn't mentioned in AGENTS.md, the README or the Makefile.** |

## What's broken or missing

1. **`make check` will fail.** `Paging.PageCount` returns `total / pageSize + 1` (`src/Tarnquill.Core/Paging.cs:13`). That gives 3 for `(10, 5)` where 2 is expected, and 1 for `(0, 5)` where 0 is expected. It should round up instead: `(total + pageSize - 1) / pageSize`. I worked this out from the code; I haven't run it.
2. **A second comment on the same item overwrites the first.** The outbox file is named only by item id (`ItemCommentCommand.cs:25`), so a later comment silently replaces an earlier one that hasn't been sent.
3. **Nothing sends the outbox.** No code reads `TARNQUILL_FORGE_TOKEN` or `TARNQUILL_FORGE_URL`. The docs also disagree: the README names the URL variable and AGENTS.md names the token. Comments only pile up locally. To finish this you'd need:
   - a `tq outbox list` command;
   - a `tq outbox send` command that reads the token from the environment and supports `--dry-run`.
4. **None of the three commands meets the CLI contract.** None has `--help` or `--json`. `item comment` writes files but has no `--dry-run`. Exit codes are mostly right.
5. **`tq commit` can't be used by scripts or agents.** It only takes input from prompts, so anything automated has to call `git commit` directly. It's worth deciding whether to add `--type`/`--message` flags (AGENTS.md currently says no flags skip the prompts) or to document that git is the fallback.
6. **`tq env check` is incomplete.** It only checks for git. It should also check:
   - `dotnet`, with the .NET 10 SDK;
   - `bash` or `pwsh`, depending on the platform;
   - whether the forge token and URL are set.
7. **`clean-outbox.sh` needs work.** It has no pwsh version. It deletes files with no `--dry-run` and no confirmation. It's also undocumented. I'd turn it into `tq outbox clear --dry-run`, which works on every platform, or at least add a Makefile target and an AGENTS.md entry.
8. **Smaller gaps:**
   - There are no checks for the CLI; only `Paging` is tested.
   - There's no CI workflow.
   - There's no formatting or lint step, such as `dotnet format --verify-no-changes`.

## What I'd do first

Fix `Paging`, which is a one-line change, so `make check` passes. Then fix the comment overwrite and build the outbox list/send/clear commands. Those turn `item comment` into something that actually works. After that, bring all commands up to the contract and expand `env check`.

I can start on any of these if you'd like.
