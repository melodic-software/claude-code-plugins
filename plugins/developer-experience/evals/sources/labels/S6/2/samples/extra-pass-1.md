### Assistant final message, turn 1

All six tools are still needed; I'd delete nothing. I only read the files.

| Tool | Verdict | Evidence |
|---|---|---|
| `scripts/build.sh` | Keep | `Makefile:4` (`build` target runs it); `AGENTS.md:8` names it as the build. |
| `scripts/build.ps1` | Keep | `AGENTS.md:8` names it as the Windows build; it is the pwsh twin of `build.sh`. |
| `scripts/clean-outbox.sh` | Keep | It empties `.tarnquill/outbox/`, which `src/Tarnquill.Cli/Commands/ItemCommentCommand.cs:24-27` writes to; nothing else clears it. |
| `Makefile` | Keep | `AGENTS.md:8-10` and `README.md` route build, check and the CLI through it. |
| `tq` CLI | Keep | `src/Tarnquill.Cli/Program.cs:16-23` dispatches `commit`, `item comment`, `env check`; `Makefile:10` runs it. |
| `tests/Tarnquill.Core.Checks` | Keep | `Makefile:7` (`check` target) runs it; `Tarnquill.sln` includes it. |

Side note: `make check` currently fails on `Paging.PageCount` (`src/Tarnquill.Core/Paging.cs`), which is a bug in the library, not a reason to drop the checks.
