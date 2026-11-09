---
bump: minor
---

### Added

- `/source-control:pull-request reassess` judges whether one open pull request should still land, even when it is green and mergeable, and returns `continue`, `rework` or `close` with its goal, base range and the pull requests it searched. It reports only unless `--act` carries out the verdict.
