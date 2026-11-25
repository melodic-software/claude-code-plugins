---
bump: patch
---

### Fixed

- `read-pr.sh view --diff` reads a pull request of any size: it reads the diff from the compare endpoint between the pull request's base and head commits, so a pull request over 300 files no longer fails with HTTP 406 ([#19124](https://github.com/melodic-software/claude-code-plugins/issues/19124)). The merge-risk, explain-change and PR-mode quality-gate reviews that read the diff through it now work on large pull requests.
