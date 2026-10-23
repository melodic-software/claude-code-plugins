---
bump: minor
---

### Removed

- `/debugging:analyze-profile` no longer records profiles: capture mode, the `capture <symptom and process>` argument, `reference/capture-by-symptom.md` and the three capture skill evals and two capture plugin eval cases are gone. With no artifact in hand the skill routes the recording to `/app-control:drive capture --kind <trace|cpu|heap>` and reads the file it brings back. A new eval case checks that a capture request names `/app-control:drive capture` and runs no profiler.
- `prerequisites.json` drops the record-only profilers (py-spy, jcmd, dotnet-stack, heaptrack, gdb, sample, spindump, leaks) and no longer lists node for analyze-profile; the remaining exporters (memray, jfr, dotnet-trace, dotnet-gcdump, go, perf, addr2line) describe only reading or converting an existing file.
