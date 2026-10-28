---
bump: patch
---

### Fixed

- `/source-control:babysit-prs`: the post-merge judge again excuses an advisory bash suite whose warning carries a title (`::warning title=<suite>::<suite> failed (exit N) but is advisory`), the form `scripts/run-plugin-tests.sh`'s `suite_annotate` prints since #10728. Before, only a bare `::warning::` or a rendered `##[warning]` line matched, so a raw log line marked an advisory suite as failed.
