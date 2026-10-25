---
bump: patch
---

### Fixed

- `/review:code-review` and `/review:security-review` read the CI lane's full-diff file to its last line, paging on with `offset` and `limit` when a Read returns only part of it, so a large pull request is never reviewed from its first page alone ([code-review SKILL.md](https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/review/skills/code-review/SKILL.md)).
