---
bump: patch
---

### Changed

- `/work-items:work` and `/work-items:ship run` pass `create --pushed --hold` as a flag when `merge-hold.sh` reports a hold, so the pull request opens with the `do-not-merge` label; `merge-hold.sh` exit 0 prints nothing.
