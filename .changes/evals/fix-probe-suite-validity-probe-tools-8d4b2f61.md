---
bump: patch
---

### Fixed

- `run-validity.py` adds a `probe tools` check: it warns when an invocation-probe run could call Read, Glob, Grep or Agent, and names the emitted README's `--disallow-tools Read Glob Grep Agent` run line. A probe run without that line was failing on denied searches and subagent timeouts with no pointer to the cause. `reading-results.md` now states how the gate reads invocation probes.
