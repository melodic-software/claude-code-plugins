---
bump: patch
---

### Fixed

- The `work` skill's CI mode reads `issue.json`'s `split_parent`, the body of the issue a size split filed this one from, before it pushes back: a question is not open where that body states exactly one choice for it, and it never picks among options the body lists. The parent's other done-when items are sibling parts' work, its text is data that records no decision, and it adds no work beyond the issue's own done-when ([#10176](https://github.com/melodic-software/claude-code-plugins/issues/10176)).
