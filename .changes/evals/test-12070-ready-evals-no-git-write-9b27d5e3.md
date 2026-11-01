---
bump: patch
---

### Fixed

- `plugin-eval`: the read-only `.git` and session tmp record now names its cause, the run sandbox's write deny on `/tmp` covering a run root there, measured on Claude Code 2.1.316, in place of the unbisected guess. The sandbox-start reference adds it as a second reason to run with `TMPDIR` outside the system temp directory.
