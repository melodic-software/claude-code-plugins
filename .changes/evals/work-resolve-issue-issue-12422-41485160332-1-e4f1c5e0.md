---
bump: patch
---

### Fixed

- `run-validity.py`'s `session started` check fails any run whose trace shows a Bash result reporting a read-only file system, or a skill's pre-computed command failing (`Shell command failed for pattern` in a `local-command-stderr`), so the run reads as a harness failure, not a scored miss (#12422).
- `plugin-eval` records a Claude Code 2.1.316 gotcha: when cases grant Bash or load a skill with a pre-computed line, a run's `TMPDIR` must not sit under `/tmp` or `/var/tmp`, where the workspace is read-only, with a recheck trigger in `records.md` (#12422).
