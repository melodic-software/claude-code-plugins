---
bump: patch
---

### Fixed

- `/source-control:babysit-prs`: the merge gate, the review evidence and the cost-hold read accept the review lanes' checks under the synced callers' display names, `PR Review Security / security-review` and `PR Review / claude-review-status`, beside `pr-review-security / security-review` and `pr-review / claude-review-status`, so a repository whose caller job carries a display name no longer reads its security review as not succeeded and never arms auto-merge. The `/source-control:pull-request` merge script and the gate docs name the same checks.
