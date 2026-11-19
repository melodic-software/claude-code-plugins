---
bump: patch
---

### Fixed

- `run-validity.py`'s `programs started` check no longer fails a run for `command not found` on an interpreter the case's skill never names (in its files or the case's `allowed_tools`), such as a run that typed `python`, found only `python3` and went on. That miss is now a warning; a missing interpreter the skill does name, and any mise shim error, still fail. The detail line lists every program that failed to start in a run, not only the first ([#17351](https://github.com/melodic-software/claude-code-plugins/issues/17351)).
