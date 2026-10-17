---
bump: minor
---

### Changed

- `/review:code-review` reads the issues a pull request closes and reports each acceptance criterion the change leaves unmet (blocking) or untested, and reads the `.claude/rules/` files whose `paths:` match changed files as review criteria.
