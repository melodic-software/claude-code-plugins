---
bump: patch
---

### Fixed

- Reverted the post-merge run-listing split and the unreadable-head reuse. With an old floor, the
  split let the check read every run since the floor, about 1,700 GitHub calls per check, which
  exhausted the GITHUB_TOKEN pool. The check again stops as unreadable at the 1,000-run search cap.
