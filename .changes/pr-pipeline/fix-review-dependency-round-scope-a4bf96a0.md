---
bump: patch
---

### Fixed

- The pr-unblock `review-dependency` round cap counts only round markers at the pull request's current commits, so a `@dependabot recreate` or force push no longer carries the replaced head's rounds into the new one. A marker that names no head still counts.
