---
bump: minor
---

### Changed

- `check-skill.sh` check 3 now tracks unquoted `Use when` triggers. It splits the `Use when` clause of `description` and of `when_to_use` at commas, and warns when an item from the base ref is gone. Before, check 3 tracked only single-quoted phrases.
- `check-skill.sh` check 12 no longer warns that `Use when` triggers are not single-quoted, because check 3 now covers unquoted triggers.
