---
bump: patch
---

### Fixed

- The interview page's Decide list now fades its top or bottom edge when rows are scrolled out of view past that edge. With every row in view, it shows no fade. The Rec row clamps to four lines, so a long recommendation no longer fills the list. When the clamp cuts the text, a Read all button opens the whole recommendation in a dialog ([#11649](https://github.com/melodic-software/claude-code-plugins/issues/11649)).
