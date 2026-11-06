---
bump: minor
---

### Changed

- `merge.verify-capture.app` is unset in this repository, so pr-verify runs no CI capture and its judges record `capture: no-app` without waiting. Screenshots of a UI-surface change come from a local capture on the building session's signed-in subscription. Setting `app: claude-code-plugins` switches the CI capture back on.
