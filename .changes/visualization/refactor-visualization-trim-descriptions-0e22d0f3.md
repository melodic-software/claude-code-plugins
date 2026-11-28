---
bump: patch
---

### Changed

- Trim `visualization` skill frontmatter descriptions (`present` 498 -> 302, `visualize` 969 -> 385; total 1,467 -> 687 chars). The `visualize` description keeps the full `ClaudeDesign` routing clause: the built-in tool only when the person names, links, or asks for work in an existing claude.ai/design project; otherwise this skill renders its own output.
