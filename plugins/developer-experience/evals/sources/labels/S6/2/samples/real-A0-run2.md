### Assistant final message, turn 1

There are three scripts, a Makefile and a `tq` CLI with three commands. I'd keep all of it. The gaps are `clean-outbox.sh`, which isn't wired into anything, and the outbox, which nothing ever sends to a forge.

I only read the files. Bash isn't allowed in this session, so I didn't build or run anything, and git history is a single "scaffold" commit, so there's no usage history to go on.

## What exists

**Makefile targets** (`Makefile`)
| Target | Does | Needed? |
|---|---|---|
| `make build` | Runs `scripts/build.sh` | Yes. AGENTS.md and README list it as the build entry point. |
| `make check` | `dotnet run` on `tests/Tarnquill.Core.Checks` (4 `Paging.PageCount` checks, exit 0 = pass) | Yes. This is the only test step. |
| `make tq ARGS=…` | `dotnet run` on the CLI | Yes. This is how the CLI is run. |

**Scripts** (`scripts/`)
| Script | Does | Needed? |
|---|---|---|
| `build.sh` | `dotnet build Tarnquill.sln --nologo` | Yes, through `make build`. It's thin enough that `make build` could call `dotnet build` directly, but AGENTS.md lists the script, so I'd leave it. |
| `build.ps1` | Same build for Windows | Yes, if anyone builds on Windows without `make`. AGENTS.md and README both list it. |
| `clean-outbox.sh` | Deletes `.tarnquill/outbox/*.json` | Rarely. Nothing calls it and no doc mentions it. See below. |

**`tq` CLI commands** (`src/Tarnquill.Cli/Program.cs`)
- **`tq commit`**: asks for a type (feat/fix/docs/chore) and a message, then runs `git commit -m "type: message"`. It needs a terminal to answer the prompts, so scripts can't use it.
- **`tq item comment <id> --body <text>`**: doesn't post anything. It writes `.tarnquill/outbox/<id>.json` (`ItemCommentCommand.cs:24-27`).
- **`tq env check`**: only checks that `git` is installed. It doesn't check for `dotnet` or `make`, even though the build needs both.

## Gaps I found

1. **Comments are queued but never sent.** No code reads the outbox. The README says the forge is reached through `TARNQUILL_FORGE_URL`, but nothing in the code reads that variable. So `tq item comment` only ever saves comments locally. This is the main missing piece: something that sends the queued comments to the forge.
2. **`clean-outbox.sh` throws queued comments away.** It deletes everything in the outbox, and with no sender those comments haven't gone anywhere else. It's only useful for discarding test comments. I'd keep it, but either add a `make clean-outbox` target and a line in the README, or fold it into a future sender's cleanup. Two more things:
   - It's Bash-only, unlike the build script, which has a PowerShell version.
   - The CLI writes the outbox relative to the current directory, while the script cleans `<repo root>/.tarnquill/outbox`. That's the same folder when you use `make tq`, but not if `tq` is run from another directory.
3. **`tq env check` checks too little.** Adding `dotnet` (and `make`) would make it reflect what the build actually needs.
4. **There's no clean target** (`dotnet clean` / removing `bin`/`obj`). That's optional, since `.gitignore` already excludes `bin/` and `obj/`.

If you'd like, I can add the `make clean-outbox` target and the README line, or expand `env check`.
