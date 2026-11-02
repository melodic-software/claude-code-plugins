---
bump: patch
---

### Fixed

- `run-validity.py`'s `session started` check fails any run whose trace shows a failed Bash result reporting a read-only file system in the run's workspace or `TMPDIR` (a relative path or one under the run's sandbox; other paths are read-only by design), or a skill's pre-computed command failing (`Shell command failed for pattern` in a `local-command-stderr`), so the run reads as a harness failure, not a scored miss (#12422).
- `plugin-eval` records a Claude Code 2.1.316 gotcha: when cases grant Bash or load a skill with a pre-computed line, a run's `TMPDIR` must not sit under `/tmp` or `/var/tmp`, with a recheck trigger in `records.md` (#12422).
