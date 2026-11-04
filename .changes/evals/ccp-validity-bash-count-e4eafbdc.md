---
bump: patch
---

### Changed

- `plugin-eval`'s `run-validity.py` prints a count-only `bash ran:` line before the verdict: per
  arm, how many runs got a Bash result that was neither a permission denial nor a sandbox start
  failure, with unreadable traces counted as `unknown` and runs offered no Bash as `n/a`. The
  `validity.txt` of a dispatched eval and of a hill-climb pass keeps that line beside the verdict.
