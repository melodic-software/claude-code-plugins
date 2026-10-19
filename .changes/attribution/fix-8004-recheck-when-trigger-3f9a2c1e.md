---
bump: patch
---

### Fixed

- `check-stamps.sh --trigger-less` now counts an inline `recheck when <condition>` clause and a `Recheck:` label (bold or plain) followed by a condition as a stated recheck trigger, so such files are no longer reported as `rule-trigger-less-stamp`. A bare `recheck` with no condition still does not count.
