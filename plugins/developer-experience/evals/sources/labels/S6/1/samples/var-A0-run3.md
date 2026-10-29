### Assistant final message, turn 1

I read the repo but couldn't run anything, because Bash is blocked in this session. So nothing below has been executed; it's all from reading the files.

## What's here

| Item | What it does | Wired into |
|---|---|---|
| `scripts/build.sh` | `dotnet build Tarnquill.sln` | `make build` |
| `scripts/build.ps1` | The same build, for Windows | Mentioned in the docs only |
| `scripts/clean-outbox.sh` | Deletes `.tarnquill/outbox/*.json` | Nothing: no make target, not in README or AGENTS.md |
| `make check` | Runs `tests/Tarnquill.Core.Checks` | — |
| `make tq ARGS=…` | Runs the `tq` CLI | — |
| `tq commit` | Asks for a type (feat/fix/docs/chore) and a message, then runs `git commit -m "type: msg"` | — |
| `tq item comment <id> --body <text>` | Writes a JSON file to `.tarnquill/outbox/<id>.json` | — |
| `tq env check` | Checks that `git` is installed | — |

## Which we still need

**Keep: `build.sh`, `build.ps1`, `make check` (the `tests/Tarnquill.Core.Checks` project), `make tq`, the `Makefile` and the `tq` CLI.** These are the documented entry points. But both build scripts have a bug: they don't stop when the build fails. `build.sh` has no `set -e` and ends with `echo "Build finished."`, so `make build` exits 0 even when the build failed. `build.ps1` likely has the same problem, because its last command is `Write-Output`. Add `set -euo pipefail` to the bash script, and in the PowerShell one exit on `$LASTEXITCODE` before printing.

**`clean-outbox.sh` is still needed.** `tq item comment` only queues comments. Nothing in the repo sends them anywhere. The README mentions `TARNQUILL_FORGE_URL`, but no code reads it. As things stand, `clean-outbox.sh` just deletes comments that were never sent. Some other problems with the outbox:
- It's written relative to whatever folder `tq` is run from, while the script always cleans `<repo>/.tarnquill/outbox`. They only match when `tq` runs from the repo root (as `make tq` does).
- One file per item ID means a second comment on the same item overwrites the first.
- There's no PowerShell version of the script.

Keep the script and add a make target for it, and keep `item comment` too.

**Fine as is: `tq commit`.** It only adds a type prefix to a commit message, and because it asks questions interactively, scripts and agents can't use it. The prompt is still useful for people committing by hand.

**Needed, and worth expanding: `tq env check`.** It checks for `git` but not `dotnet`, which every build and run needs.

## Unrelated, but `make check` will fail

`Paging.PageCount` computes `total / pageSize + 1`. That gives 3 pages for 10 items at 5 per page (the check expects 2) and 1 page for 0 items (expected 0). The fix is `(total + pageSize - 1) / pageSize`.

I can fix the build scripts and `PageCount` now. For the outbox and `tq commit`, tell me whether to keep or remove them.
