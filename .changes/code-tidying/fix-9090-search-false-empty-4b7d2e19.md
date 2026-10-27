---
bump: patch
---

### Fixed

- `/code-tidying:tidy`: the open-PR throttle no longer reads a degraded search's false empty as no open tidy PRs ([#9090](https://github.com/melodic-software/claude-code-plugins/issues/9090)). `open-pr-count.sh` lists open PRs without `--search`, up to 1000, and counts `chore/tidy-*` head branches itself. A listing that reaches that limit prints `Throttle active: yes`, so tidy stops rather than adding to a backlog it could not count.
