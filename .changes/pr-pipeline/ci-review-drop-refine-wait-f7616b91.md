---
bump: minor
---

### Removed

- The hosted review lanes (`pr-review-hosted.yml`, `pr-review-security-hosted.yml`) no longer run a `wait-for-refine` job, and `.github/scripts/pr-review/wait-refine.mjs` is gone. The review job needs only `check-kill-switch` and reviews each ready head as it lands. Refine's push carries the lanes App token, so it starts a `pull_request` `synchronize` run that reviews only the files changed since the last completed review. The wait had ended at its 30-minute cap with `review: refine-timeout` and then reviewed the unrefined head anyway, adding about 29.5 minutes to each review.
