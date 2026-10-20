---
bump: patch
---

### Fixed

- The Unattended merge section documents that pr-merge refuses, as `shared-copy-sources-changed:`, a pull request carrying a shared-library canonical that main changed since its merge base, escalates it with the human-gated role label and a `babysit-merge-shared-copy-escalation` comment, and that the fix is merging main and running `scripts/sync-shared-copies.sh`. The head-moved clear removes that label once the head moves ([README.md, Unattended merge](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).
