### Assistant final message, turn 1

I couldn't run anything because shell access was denied in this session. Everything below comes from reading the code, so none of it has been run.

## What's here

| Tool | What it does | Status |
|---|---|---|
| `make build` → `scripts/build.sh` | `dotnet build Tarnquill.sln` | **Bug:** no `set -e` and no exit-code check, so it prints "Build finished." and exits 0 even when the build fails (`scripts/build.sh:4-5`) |
| `scripts/build.ps1` | The Windows version of the build | Same bug: `$LASTEXITCODE` is never checked (`scripts/build.ps1:3-4`) |
| `make check` | Runs `tests/Tarnquill.Core.Checks` | Should fail right now. `Paging.PageCount` returns `total / pageSize + 1` (`src/Tarnquill.Core/Paging.cs:13`), which gives 3 for (10,5) and 1 for (0,5) where the checks expect 2 and 0. |
| `make tq ARGS=…` | Runs the CLI | Works |
| `tq commit` | Prompts for type and message, then runs `git commit -m "type: msg"` | Interactive only, as documented. An agent can't use it, so plain `git commit -m "feat: …"` does the same job. |
| `tq item comment <id> --body <text>` | Writes `.tarnquill/outbox/<id>.json` | A second comment on the same item silently overwrites the first. The outbox path is relative to the current directory. |
| `tq env check` | Checks for `git` only | Doesn't check `dotnet`, even though the repo can't build without it |
| `scripts/clean-outbox.sh` | `rm -f .tarnquill/outbox/*.json` | **Not listed in AGENTS.md.** It's bash-only (no pwsh version), has no Makefile target, and has no `--dry-run`. |
| `ProcessRunner.Run` | The shared helper for running external processes | Fine. Both commands that start processes use it. |

## What we still need

Nothing should be deleted. Every script and command is either used or is the only way to do its job. That includes `clean-outbox.sh`, which is the only way to empty the outbox other than deleting the files by hand. The gaps are:

1. **Make the build scripts fail properly.** `set -euo pipefail` in `build.sh`, and `exit $LASTEXITCODE` in `build.ps1`. Right now a failed build looks like a pass, so this is the most important fix.
2. **Fix `Paging.PageCount`** so `make check` passes. The usual fix is `(total + pageSize - 1) / pageSize`.
3. **Make `clean-outbox` cross-platform and documented.** Add a `clean-outbox.ps1` (or make it a `tq` subcommand with `--dry-run`), a Makefile target, and an entry in AGENTS.md.
4. **Bring `tq` up to the repo's own CLI rules.** No command has `--help` or `--json`, and `item comment` writes files but has no `--dry-run`.
5. **Expand `tq env check`** to cover `dotnet` (and `pwsh` on Windows).
6. **Decide on a way to send the outbox.** Comments can be queued but nothing reads or sends them. Also, the README names `TARNQUILL_FORGE_URL` and AGENTS.md names `TARNQUILL_FORGE_TOKEN`, but the code uses neither. That's fine while the repo is offline-only, but a send command will need both.

My suggested order is 1 and 2 first (each is about one line and gets build and check working again), then 3 and 5. Items 4 and 6 are new features, so they're worth deciding as a team first. Want me to make the first two fixes?
