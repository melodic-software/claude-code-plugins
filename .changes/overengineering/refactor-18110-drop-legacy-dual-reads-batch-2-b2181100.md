---
bump: major
---

### Removed

- **Dropped legacy `.claude/` and `~/.claude/` dual-reads.** `/overengineering:audit`, `/overengineering:delta`, and `/overengineering:realign` now read only `<home>/overengineering.yaml` and `<home>/overengineering.local.yaml` and no longer read `~/.claude/overengineering.md`, `.claude/overengineering.md`, or `.claude/overengineering.local.md`.
