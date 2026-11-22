---
bump: patch
---

### Fixed

- `rename-references` audit survey describes a line-break Grep pattern run without `multiline` as reported back as a rejected pattern, not a silent loss of the form, and points at the Claude Code changelog for what Grep reports. The instruction to set `multiline: true` for Form 7 and Form 14's Setext alternative is unchanged ([#17832](https://github.com/melodic-software/claude-code-plugins/issues/17832)).
