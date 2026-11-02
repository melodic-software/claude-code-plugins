---
bump: patch
---

### Fixed

- The log-api-budget action writes each token's `api-calls` and `api-routes` notices before the per-counter `api-budget` ones, so they stay among the 10 notices of a step that become annotations; a job with two tokens and several counters (the pr-merge merge job) lost its `api-routes` lines, and with a content write its `github-token` total too.
- pr-merge's full-run cover counts pr-require-checks.yml's scheduled and hand-started full runs of main toward the 30-minute cap and as cover of main's tip; only a github-actions[bot] dispatch still covers a lane merge for the cap bypass.
- The cap comments in pr-merge.yml and pr-require-checks.yml name the lane-merge cap bypass, and the pr-pipeline config comment says the work-class lane hold covers untrusted provenance only.
