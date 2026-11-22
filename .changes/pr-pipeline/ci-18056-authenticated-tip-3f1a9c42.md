---
bump: patch
---

### Fixed

- Every `Resolve main's tip` step now reads main's tip with the job's own token instead of an anonymous `git ls-remote`, which GitHub refused with HTTP 403 from shared runner addresses. 94 steps use the ci-workflows `resolve-branch-tip` action; the 3 in the two release workflows that hold the release App key carry the same read inline, so those workflows run no ci-workflows action. A timeout or a 5xx is retried within 3 tries, and a 401 or 403 fails at once. pr-merge's carry readers take the action's `unambiguous-sha`, set only while no tag is named main. `download-full-history` sends the job token for its unshallow and base-ref fetches too.
