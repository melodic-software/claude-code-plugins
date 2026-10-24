---
bump: patch
---

### Changed

- `/work-items:work` CI mode lists the parts of the issue its PR leaves for later work in a new `remaining` array in `work-outcome.json`, in place of the `link` field. The lane opens a `Refs:` PR only when `remaining` names something, and closes the issue otherwise. The issue's own `Refs:` or `Depends on:` lines are not remaining work, and a recorded keep-`Refs` decision names the part it leaves open there.
