---
bump: patch
---

### Fixed

- The unattended merge gate lists each review lane's runs only from the pull request's creation time on. A reused branch (such as the release branch) no longer reads every earlier pull request's runs, which cost about 4,000 lanes App calls per gate and exhausted its rate limit.
