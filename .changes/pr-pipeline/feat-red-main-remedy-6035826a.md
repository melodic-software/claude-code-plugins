---
bump: minor
---

### Added

- The optional `red-main.remedy` key, `rollback` (default) or `fail-forward`. Under `fail-forward` the red-main report plans no revert: its decision is `human`, naming the remedy, and a person or a fix pull request repairs `main` ([README.md, Red main](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#red-main)).
