---
bump: patch
---

### Changed

- The unattended merge gate reads the pipeline config and the git modes at a commit from a local full clone that holds it, and falls back to the contents and trees APIs only when no clone does. Within one gate process, a pull request's commit list and its commit count are read once per head and reused by the policy, the lane evidence, the verifier reader and the signature check; a list that does not end at that head is read again.
