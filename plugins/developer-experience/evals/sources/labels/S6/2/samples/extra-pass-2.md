### Assistant final message, turn 1

Here is what the repo has and whether each piece earns its place.

- **`make build` / `scripts/build.sh`**: keep. The `build` target in `Makefile` calls `bash scripts/build.sh`, and `README.md` gives it as the way to build.
- **`scripts/build.ps1`**: keep. `AGENTS.md` ("`scripts/build.ps1` on Windows") makes it the Windows path for the same build.
- **`make check` / `tests/Tarnquill.Core.Checks`**: keep. `Makefile` runs `dotnet run --project tests/Tarnquill.Core.Checks`; it is the only test step listed in `AGENTS.md`.
- **`make tq` and the `tq` CLI**: keep. `Makefile` runs `src/Tarnquill.Cli`, and `src/Tarnquill.Cli/Program.cs` wires up its three commands.
- **`scripts/clean-outbox.sh`**: keep, though it is undocumented. It deletes the JSON files that `ItemCommentCommand.cs` writes under `.tarnquill/outbox/`; without it there is no way to clear queued comments.

Nothing is dead. If you want, I can add the outbox script to `README.md` so it's discoverable.
