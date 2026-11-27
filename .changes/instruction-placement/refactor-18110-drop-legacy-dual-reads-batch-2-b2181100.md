---
bump: major
---

### Removed

- **Dropped legacy `.claude/` and `~/.claude/` suppression dual-reads and `/instruction-placement:setup apply migrate-config`.** `audit`, `delta`, `realign`, and `setup` now read only the canonical suppression cascade (`<home>/instruction-placement.yaml` and `<home>/instruction-placement.local.yaml`) and ignore `.claude/instruction-placement.md`, `.claude/instruction-placement.local.md`, and `~/.claude/instruction-placement.md`.
