---
bump: patch
---

### Added

- Eval cases `s1-branch-start-build` and `s4-migrator-build`, the build turns of scenarios S1 and S4. Each resumes a recorded plan turn that changed nothing and sends the source scenario's "Yes, go ahead.". S1's free graders check that a Write call runs git through `ProcessRunner.Run`, that no Write or Edit adds `Process.Start` or `ProcessStartInfo` outside `Infrastructure/ProcessRunner.cs`, and that a written file names `TARNQUILL_FORGE_TOKEN` and calls `GetEnvironmentVariable`. They also check that the conventions Tools section names `branch start`, that a shell call runs `tq branch start` and another runs `make check` or the checks project, and that the run created a `.cs` file under `src/Tarnquill.Cli/`. S4's free graders check that the conventions Tools section names the migration, that `pyproject.toml` still declares no dependency, and that a shell call runs the helper itself rather than only its tests. Items that run the built command, and the judge items whose labels grade a two-turn report, are not graded. ([#9953](https://github.com/melodic-software/claude-code-plugins/issues/9953))
