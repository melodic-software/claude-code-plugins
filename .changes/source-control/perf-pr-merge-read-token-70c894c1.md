---
bump: patch
---

### Changed

- The unattended merge gate reads its review evidence (the pull request's timeline and comments, and the review-lane runs with their attempts, jobs and annotations) under `BABYSIT_VERIFY_GH_TOKEN` when it is set, as the verdict reader's Actions reads already do, so those GETs no longer spend the lane App's rate limit. Every write keeps the process token; without the variable every read does too. `gh_json`, `fetch_paginated_api` and `collect_lane_runs` take an optional `env_overrides`.
