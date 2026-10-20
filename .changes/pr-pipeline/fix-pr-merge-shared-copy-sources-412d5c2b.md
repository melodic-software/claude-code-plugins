---
bump: patch
---

### Fixed

- The Unattended merge section documents that pr-merge refuses, as `shared-copy-sources-changed:`, a pull request carrying a shared-library canonical that main changed since its merge base, and that the fix is merging main and running `scripts/sync-shared-copies.sh` ([README.md, Unattended merge](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).
