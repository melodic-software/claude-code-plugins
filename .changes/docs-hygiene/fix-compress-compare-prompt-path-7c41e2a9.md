---
bump: patch
---

### Fixed

- **`/docs-hygiene:compress compare` reads the labeler prompt by its full path.** The step now names `${CLAUDE_SKILL_DIR}/context/compare-prompt.md` and forbids searching the plugin's install directory for it; a session that could not find the relative path searched there, was denied, and wrote the labeler's brief itself.
