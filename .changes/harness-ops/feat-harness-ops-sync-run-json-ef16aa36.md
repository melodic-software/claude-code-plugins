---
bump: patch
---

### Changed

- `plugins` sync now calls `claude plugin install` and `claude plugin update` with `--json` and read the result line: an update's `updateOutcome` and `newVersion` decide whether it moved and to which version, so a reworded CLI sentence no longer misfiles an already-current id. Unset userConfig options and a disabled-by-default install have no field of their own, so those two are still read from the result's `message`. A CLI that prints no result line is still read from its text.
