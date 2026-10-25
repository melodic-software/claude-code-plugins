---
bump: minor
---

### Changed

- **`work-items` declares `implementation` as a dependency.** `/work-items:ship run` dispatches its ready set through `/implementation:implement-dispatch` and has no fallback without it, so the manifest's `dependencies` now lists `implementation`, and installing `work-items` installs it.
