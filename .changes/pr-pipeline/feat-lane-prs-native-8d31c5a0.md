---
bump: minor
---

### Changed

- `merge.lane-prs` (default `native`) leaves the lanes App's pull requests to GitHub's native auto-merge: pr-merge's `merge` job no longer lists them, so its gate never scores, escalates or enqueues one. Adopted owner pull requests and Dependabot's are gated as before. `gate` restores the earlier listing, and this repository sets it until `ci-status` or `enable-auto-merge` enforces the pr-verify verdict and the post-merge check judges native merges ([README.md, Native auto-merge](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#native-auto-merge)).
