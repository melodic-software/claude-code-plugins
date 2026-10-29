### Assistant final message, turn 1

Here's what's in the repo. I couldn't run commands in this session, so everything below comes from reading the source. None of it was executed.

## What exists

**Make targets** (`Makefile`)
| Target | What it does |
|---|---|
| `make build` | Runs `scripts/build.sh` |
| `make check` | Runs `tests/Tarnquill.Core.Checks`, a console program that exits 0 when every check passes |
| `make tq ARGS=...` | Runs the CLI with `dotnet run` |

**Scripts** (`scripts/`)
| Script | What it does | Used by |
|---|---|---|
| `build.sh` | `dotnet build Tarnquill.sln --nologo` | `make build`, README, AGENTS.md |
| `build.ps1` | A duplicate of `build.sh` | README, AGENTS.md |
| `clean-outbox.sh` | Deletes `.tarnquill/outbox/*.json` | Nothing. No make target and no docs mention it |

**`tq` CLI commands** (`src/Tarnquill.Cli`)
| Command | What it does |
|---|---|
| `tq commit` | Asks for a change type (feat/fix/docs/chore) and a message, then runs `git commit -m "type: msg"` |
| `tq item comment <id> --body <text>` | Writes `.tarnquill/outbox/<id>.json`. It only queues the comment and never sends it |
| `tq env check` | Checks that `git` is installed |

## Which ones we still need

The code alone doesn't say what the team relies on, so these are my recommendations. I haven't changed anything.

- **Keep `make build`, and drop `build.ps1`.** It duplicates `build.sh`; both are thin wrappers around `dotnet build`. To drop it, you'd change the `build` target to call `dotnet build` directly and update README and AGENTS.md.
- **Keep `make check` and `make tq`.** They're the main entry points.
- **Decide on the outbox workflow before keeping or deleting `clean-outbox.sh`.** No code in the repo ever sends the outbox. The README says the forge is reached through `TARNQUILL_FORGE_URL`, but no code reads that variable. As things stand:
  - `tq item comment` queues comments that never get posted. A second comment on the same item overwrites the first, because the file is always `<id>.json`.
  - `clean-outbox.sh` deletes those unsent comments without asking, and has no Windows version.

  If the forge integration is still planned, keep both and add a send step. If it was dropped, remove both along with the `.tarnquill/` line in `.gitignore`.
- **`tq commit` is optional.** It only adds a type prefix to `git commit -m`. It's interactive, so scripts and agents can't use it. Keep it only if people actually use it.
- **Keep `tq env check`, but it needs work.** It checks for `git` but not `dotnet`, which every make target needs. It also doesn't check `TARNQUILL_FORGE_URL`.

## Bug found while reading

`make check` will fail as the code stands. `Paging.PageCount` (`src/Tarnquill.Core/Paging.cs:13`) computes `total / pageSize + 1`, so `PageCount(10, 5)` returns 3 instead of 2 and `PageCount(0, 5)` returns 1 instead of 0. Rounding up instead (`(total + pageSize - 1) / pageSize`) gives the values the checks expect.

I can fix the paging bug, remove the outbox pieces, or extend `env check` — which do you want?
