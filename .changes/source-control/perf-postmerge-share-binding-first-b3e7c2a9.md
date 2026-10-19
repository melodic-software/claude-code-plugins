---
bump: patch
---

### Changed

- The pr-merge gate checks a shared post-merge answer's binding (identity, self logins, lane, floor) before its age, so a candidate on another floor is refused as `floor-differs` and no longer replaces a stale run answer with its own recompute; the next main-floor candidate refreshes the run's answer and later ones reuse it. Every verdict is unchanged.
