---
bump: patch
---

### Changed

- `babysit-prs`: `red-main.confirm-wait-minutes` now defaults to 55 and accepts up to 60, matching pr-merge's 30-minute schedule. The post-merge lane re-run lookback (confirm wait plus 50 minutes) is therefore 105 minutes by default.
