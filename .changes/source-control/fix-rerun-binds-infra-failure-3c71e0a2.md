---
bump: patch
---

### Fixed

- `/source-control:babysit-prs` binds a review lane's second attempt after the first failed on a rejected Claude credential (the lane's own `failure-class=auth` failure line), as it already did after a usage limit or a spent key, which the lane reports as `rate-limit`. Such a re-run was refused as `rerun-not-allowed`, so a pull request whose review was re-run after a credential outage stayed held. The merge gate still re-runs a review only after a rate limit, so a re-run before the secret is fixed cannot spend the one allowed attempt.
