---
bump: patch
---

### Fixed

- `/source-control:babysit-prs`: the merge gate, the review evidence and the cost-hold read accept the review lanes' checks under ci-workflows' Title Case job names, `<caller> / Status` for pr-review-cli.yml and `<caller> / Claude` for pr-review.yml and pr-review-security.yml, beside the earlier `review-status`, `claude-review-status` and `security-review` names, so neither lane reads as not succeeded once those jobs are renamed. `Status` and `Claude` are shared by both lanes, so each counts only under the lane's own callers. The `/source-control:pull-request` merge script and the gate docs name the same checks.
