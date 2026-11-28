---
bump: patch
---

### Changed

- `/work-items:work` and `/work-items:ship run` pass `create --pushed --hold` as a flag when `merge-hold.sh` reports a hold, so the pull request opens with the `do-not-merge` label; `merge-hold.sh` exit 0 prints nothing.
- `/work-items:work` no longer lists a hold among the `ready` refusals that leave a pull request a draft: the only hold-related draft is a `do-not-merge` label that failed to set at create.
