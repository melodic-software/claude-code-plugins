---
bump: patch
---

### Fixed

- The comment lint passes actionlint's inline suppression directives (`actionlint:ignore`, `actionlint-ignore` and their `-next-line` forms) as machine-read directives instead of flagging them; a plain comment that names actionlint is still flagged ([#19742](https://github.com/melodic-software/claude-code-plugins/issues/19742)).
