---
bump: minor
---

### Removed

- `/debugging:analyze-profile` no longer records profiles: capture mode, the `capture <symptom and process>` argument, `reference/capture-by-symptom.md` and the three capture skill evals and two capture plugin eval cases are gone. With no artifact in hand the skill stops and names `/app-control:drive capture --kind <trace|cpu|heap|threads>` as the command for the person to run, and never invokes drive or a recorder itself, attended or not. Two new eval cases, one attended and one unattended, check that a capture request names `/app-control:drive capture`, runs no profiler and makes no Skill call to drive.
- `prerequisites.json` drops the record-only profilers (py-spy, jcmd, dotnet-stack, heaptrack, gdb, sample, spindump, leaks) and no longer lists node for analyze-profile; the remaining exporters (memray, jfr, dotnet-trace, dotnet-gcdump, go, perf, addr2line) describe only reading or converting an existing file.

### Added

- `reference/formats/other-formats.md` gains rows for thread dumps (py-spy dump, `jcmd` thread dump, dotnet-stack, Go goroutine dump, gdb `thread apply all bt`): how to recognize each and which blocked or waiting frames and lock owners to read.

### Changed

- Exports are written under the run's `${work:?}` directory, so cleanup deletes only that directory.

- When `mktemp -d` fails because the temporary directory is read-only, `/debugging:analyze-profile` makes its SQLite work directory with `mktemp -d "<writable dir>/profile.XXXXXX"` under a writable directory outside the repository, so the `rm -r` at cleanup only ever deletes a directory this run created.
