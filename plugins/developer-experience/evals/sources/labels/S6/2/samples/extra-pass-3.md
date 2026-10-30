### Assistant final message, turn 1

Short answer: everything stays. Inventory and reasons:

1. `Makefile` (targets `build`, `check`, `tq`): needed. `AGENTS.md` lines 7-10 tell contributors to use exactly these targets.
2. `scripts/build.sh`: needed; `Makefile` line 4 calls it.
3. `scripts/build.ps1`: needed; same build for PowerShell, listed in `AGENTS.md` line 8 for Windows.
4. `scripts/clean-outbox.sh`: needed; it removes `.tarnquill/outbox/*.json`, the files `src/Tarnquill.Cli/Commands/ItemCommentCommand.cs` creates.
5. `tq` (`src/Tarnquill.Cli`, AssemblyName `tq` in `Tarnquill.Cli.csproj`): needed; `Makefile` line 10 runs it and `README.md` documents it.
6. `tests/Tarnquill.Core.Checks`: needed; `Makefile` line 7 runs it as `make check`.

I didn't change anything.
