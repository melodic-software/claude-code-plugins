---
bump: patch
---

### Fixed

- `/playbooks:repo-sweep`: off a sweep branch, `state.sh` no longer reads a degraded search's false empty as no sweep PR, which would have filed a duplicate sweep ([#9090](https://github.com/melodic-software/claude-code-plugins/issues/9090)). It lists open PRs without `--search`, up to 1000, and keeps its own head-branch filter. A listing that reaches that limit exits 1 (an error), never 10 (no sweep PR).
