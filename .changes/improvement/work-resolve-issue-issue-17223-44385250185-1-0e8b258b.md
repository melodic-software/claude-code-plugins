---
bump: patch
---

### Fixed

- `setup apply` no longer writes `.claude/improvement.md` before asking: it drafts values from the invocation and the repository, then asks the first interview question with its recommendation before any write, even when every value looks unambiguous ([#17223](https://github.com/melodic-software/claude-code-plugins/issues/17223)).
