---
bump: patch
---

### Fixed

- babysit-prs: the pr-merge lane's Dependabot gate takes a CDN pins sync commit only when its message is exactly the `cdn-pins-sync` row's: the subject `Sync the CDN pins to the bumped manifest on <head ref> [dependabot skip]` on the pull request's own head ref, then the one trailer `Lane-Activity: pr-unblock/review-dependency`. A `[dependabot skip]` commit with another row's subject, another branch, or a missing or different trailer now refuses (`cdn-sync-message`, `cdn-sync-trailer`).
