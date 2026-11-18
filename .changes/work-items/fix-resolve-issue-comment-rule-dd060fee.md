---
bump: patch
---

### Fixed

- `/work-items:work --ci` writes no new code comment unless the repository's rule for added comments allows it and the comment lint accepts its shape, so the `work-resolve-issue` lane stops opening pull requests that lint refuses.
