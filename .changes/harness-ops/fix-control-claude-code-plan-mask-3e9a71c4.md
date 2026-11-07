---
bump: patch
---

### Fixed

- The control-claude-code `## Mask` banner line hides any plan name after `· Claude` up to a border, not a fixed list of plan names, so a startup banner showing a plan the list did not name (such as `Claude Ultra`) no longer reaches a published screenshot ([#11364](https://github.com/melodic-software/claude-code-plugins/issues/11364)).
- The control-claude-code screen mask runs each masked value's stars through the end of its row segment (the next box-drawing border or the row's last column), so a screenshot no longer shows a hidden value's length, such as the plan name's or the usage figures'.
