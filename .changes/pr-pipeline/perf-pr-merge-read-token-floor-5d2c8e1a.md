---
bump: patch
---

### Added

- `merge.read-token-floor` (default 0.3): the pr-merge gate reads its review evidence (timeline, comments, review-lane runs with their attempts, jobs and annotations) with `GITHUB_TOKEN` only while that token has at least this share of its hourly core limit left. Below it, or when the limit cannot be read, those reads use the lane App token, as they did before. The floor is only an early switch: when one of those reads is refused for a rate limit (a 429, or a 403 naming one), the gate reads that candidate's evidence again with the lane App token and marks `GITHUB_TOKEN` spent in the run cache for later candidates. Either token reads the same data, so no gate decision changes. The value is read at the default branch head. The repository's `GITHUB_TOKEN` pool, 1,000 requests an hour shared by every job, ran out on 2026-10-23 once these reads moved onto it.
