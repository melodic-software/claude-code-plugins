---
bump: patch
---

### Changed

- The babysit merge gate's dequeue report names the reason the merge queue removed the pull request, and for `branch_protection_failure` names the likely cause: a body line GitHub's 72-character squash wrap starts with the word `committer` and a space, which breaks the squash commit's signature.
