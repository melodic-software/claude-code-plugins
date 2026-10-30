---
type: llm
focus: { source: file, path: docs/conventions/developer-experience.md }
arm: with-only
---

Rubric item: true facts: every command, script and helper the conventions name exists in the fixture.

The agent was asked to write down the developer tooling conventions of the .NET repository `tarnquill`. The text to grade is the conventions it wrote: the contents of the conventions file, or a diff of the markdown files it wrote. When there is no such text (the file is missing or empty), FAIL.

Fixture facts: files: `AGENTS.md`, `Makefile`, `README.md`, `Tarnquill.sln`, `scripts/build.sh`, `scripts/build.ps1`, `scripts/clean-outbox.sh`, `src/Tarnquill.Cli/Program.cs`, `src/Tarnquill.Cli/Tarnquill.Cli.csproj` (AssemblyName `tq`), `src/Tarnquill.Cli/Commands/CommitCommand.cs`, `src/Tarnquill.Cli/Commands/EnvCheckCommand.cs`, `src/Tarnquill.Cli/Commands/ItemCommentCommand.cs`, `src/Tarnquill.Cli/Infrastructure/ProcessRunner.cs` (method `ProcessRunner.Run(file, args)`), `src/Tarnquill.Core/Paging.cs`, `src/Tarnquill.Core/Tarnquill.Core.csproj`, `tests/Tarnquill.Core.Checks/Program.cs`, `tests/Tarnquill.Core.Checks/Tarnquill.Core.Checks.csproj`. Makefile targets: `build` (bash scripts/build.sh), `check` (dotnet run --project tests/Tarnquill.Core.Checks), `tq` (dotnet run --project src/Tarnquill.Cli -- $(ARGS)). `tq` subcommands: `commit` (interactive, no flags), `item comment <id> --body <text>` (writes `.tarnquill/outbox/<id>.json`), `env check`. Standard tools (`dotnet`, `git`, `bash`, `pwsh`, `make`) exist. The forge settings are environment variables `TARNQUILL_FORGE_URL` and `TARNQUILL_FORGE_TOKEN`.

List every command, subcommand, flag, script, file and helper the conventions text names as existing in this repo, and check each against the fixture facts. Names of things the text says do not exist, or proposes for the future, do not count against it. PASS when every named item exists as described; FAIL when any named command, subcommand, flag, script or helper does not exist (for example an invented `tq` subcommand or flag, a missing script, or a wrong Makefile target).
