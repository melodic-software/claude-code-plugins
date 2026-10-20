---
bump: patch
---

### Changed

- The babysit merge gate's dequeue report names the reason the merge queue removed the pull request, and for `branch_protection_failure` names the likely cause: a body line GitHub's 72-character squash wrap starts with a git header keyword, which breaks the squash commit's signature.
