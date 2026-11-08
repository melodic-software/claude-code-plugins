---
bump: patch
---

### Fixed

- The post-merge accounting labels follow the org label grammar (`axis: value`): record-path merges get `merge-path: <path>` and reverted ones `post-merge: reverted`. The label plan and the rollup still read the older `merge-path:<path>` and `post-merge:reverted`, so pull requests labeled before the rename keep counting. The old names failed github-iac's grammar test, so they could not be declared and each apply would prune them from every merged pull request.
