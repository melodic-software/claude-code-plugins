---
bump: patch
---

### Added

- Two eval cases check that a CI code review of a full-diff file larger than one Read still finds the bug: `code-review-large-diff-pages-to-end` puts it in an ordinary file in the diff's last third, `code-review-large-diff-middle-file` in a service file mid-diff ([evals](https://github.com/melodic-software/claude-code-plugins/tree/main/plugins/review/evals)).
