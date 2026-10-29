### Assistant final message, turn 1

I read every file in the repo but couldn't run anything (Bash was denied), so none of this has been executed.

## What exists

| Tool | What it does | Notes |
|---|---|---|
| `make build` → `scripts/build.sh` / `scripts/build.ps1` | `dotnet build Tarnquill.sln` | Works on both bash and pwsh. |
| `make check` | Runs the `tests/Tarnquill.Core.Checks` console project | Will probably fail today; see below. |
| `make tq ARGS=…` | `dotnet run` of the CLI | |
| `tq commit` | Asks for type (feat/fix/docs/chore) and a message, then runs `git commit -m "type: msg"` | Interactive only, as documented. |
| `tq item comment <id> --body <text>` | Writes `.tarnquill/outbox/<id>.json` | Saves the comment locally; nothing is sent. |
| `tq env check` | Checks that `git` is installed | |
| `scripts/clean-outbox.sh` | `rm -f .tarnquill/outbox/*.json` | **Not listed in AGENTS.md.** |
| `ProcessRunner.Run` | Shared helper for running external processes | Used by `commit` and `env check`. |

## Which we still need

All of them. Nothing is redundant. But several don't meet the repo's own rules:

1. **`scripts/clean-outbox.sh` has no `.ps1` version.** The Platforms rule says Windows uses pwsh, so Windows users can't clear the outbox. It also deletes files with no `--dry-run` and isn't documented. Either add `clean-outbox.ps1` and document both, or better, replace the script with a `tq outbox clear --dry-run` command so it works on every platform.
2. **`tq item comment` doesn't meet the CLI contract.** It writes files but has no `--dry-run`, `--json` or `--help`. Its file is named after the item id, so a second comment on the same item silently overwrites the first one still in the outbox (`ItemCommentCommand.cs:25`). It also writes relative to the current directory, while `clean-outbox.sh` uses the repo root, so running `tq` from a subdirectory puts the outbox somewhere the cleanup script won't look.
3. **Nothing can list or send the outbox.** Comments can be saved and deleted, but not reviewed or sent. If the outbox is meant to be sent to the forge eventually, a `tq outbox list` / `send` pair is the missing piece.
4. **`tq env check` only checks `git`.** It should also check `dotnet` (needed to build) and `pwsh` on Windows.
5. **No `--help`.** `tq --help` hits the default branch and exits 2. Each command should accept `--help`.
6. **The docs disagree on the forge variable.** README mentions `TARNQUILL_FORGE_URL`, AGENTS.md mentions `TARNQUILL_FORGE_TOKEN`, and no code reads either one. Pick one set and document it in both places.

## Not a tooling problem, but you'll hit it

`Paging.PageCount` returns `total / pageSize + 1` (`src/Tarnquill.Core/Paging.cs:13`). That gives 3 for `(10, 5)` and 1 for `(0, 5)`, which looks like it would fail two of the four checks, so `make check` should exit 1. The usual fix is `(total + pageSize - 1) / pageSize`.

If I had to rank them: fix `PageCount` first, then items 1 and 2, because they cause real problems (missing Windows support and lost comments). The rest is closing gaps. Want me to start on any of these?
