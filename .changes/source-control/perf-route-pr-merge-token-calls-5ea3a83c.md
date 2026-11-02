---
bump: patch
---

### Fixed

- Each `gh api` rate-limit reading the babysit scripts write (`babysit_gh.py`) now carries its templated route, so a job's `api-routes` notice names the routes of the post-merge check and the merge gate instead of counting them as `other`.
- A post-merge report kept from an earlier pr-merge tick is no longer refused as `code-changed` by a commit that only changes the babysit-prs scripts' tests.
