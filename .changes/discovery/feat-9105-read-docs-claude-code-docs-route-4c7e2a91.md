---
bump: minor
---

### Changed

- `/discovery:read-docs`: its description now routes a quick question about a Claude Code feature to the bundled `claude-code-docs` skill when that skill resolves in the session, and keeps this skill for an answer that must rest on a named page's own text. A new `## Boundary` section states the split and the mutation gate, and `reference/bundled-claude-code-docs.md` records the basis. ([#9105](https://github.com/melodic-software/claude-code-plugins/issues/9105))
