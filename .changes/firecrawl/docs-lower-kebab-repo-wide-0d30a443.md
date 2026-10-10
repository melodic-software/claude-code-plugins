---
bump: patch
---

### Changed

- **The update skill's sync-state file is now `skills/update/upstream.md`**, renamed from `UPSTREAM.md` so every markdown file in the repository is lower-kebab-case (ADR 0059). `scripts/update.sh`, the skill body, its flow reference, and its evals read and write the new name.
