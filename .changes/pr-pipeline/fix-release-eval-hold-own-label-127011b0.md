---
bump: patch
---

### Fixed

- `release-eval-hold.mjs` removes `do-not-merge` only when the eval hold set it: the newest label event and an eval reason line are by the same listed human or by the lanes App, the line posted within 10 minutes after the label (`OWN_LABEL_WINDOW_MS`). A label a person or a lane added for another reason, including one re-added after an eval release, now stays (`label-not-eval-owned`) even when an eval-only reason line and a record follow it.
