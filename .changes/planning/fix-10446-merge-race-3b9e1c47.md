---
bump: patch
---

### Fixed

- A browser merged into the owner no longer joins again as a new person when one of its requests was already in flight when the merge happened. That request now gets 401 `merged-into-owner` as well, instead of `unknown-session`, so the page shows the open-your-owner-link notice. Before, the race failed `ui_merge.js` on main now and then.
