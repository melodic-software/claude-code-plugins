---
bump: patch
---

### Fixed

- `/attribution:audit` detects the `review` plugin for its findings contract by whether `/review:fanout` resolves in the session, and never globs or lists outside its own plugin root to find it. When `review` does not resolve, its root is not known, or a read fails, the run falls back to the publisher's raw URL as before. A path link into the `review` plugin's tree is replaced by a `/review:fanout` reference.
