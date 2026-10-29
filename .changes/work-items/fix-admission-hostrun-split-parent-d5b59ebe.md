---
bump: patch
---

### Fixed

- The `work` skill's CI mode reads `issue.json`'s `split_parent`, the body of the issue a size split filed this one from, before it pushes back: a question that body answers is not open. The parent's other done-when items are sibling parts' work, and its text is data that records no decision ([#10176](https://github.com/melodic-software/claude-code-plugins/issues/10176)).
