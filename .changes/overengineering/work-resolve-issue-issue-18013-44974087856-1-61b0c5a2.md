---
bump: minor
---

### Changed

- **Config moves to the convention home.** The team file is now `<home>/overengineering.yaml`
  (default `docs/conventions/overengineering.yaml`), plain YAML validated by the new
  `schemas/overengineering.schema.json`. The personal override is `<home>/overengineering.local.yaml`.
  There is no user-global file and still no `userConfig` option, because every key describes one
  repository. Realign writes suppression entries to the team file, and the audit leaves every config
  file out of its scan set.

### Deprecated

- **The old `~/.claude/overengineering.md`, `.claude/overengineering.md` and
  `.claude/overengineering.local.md` are read only during a dual-read window.** While one exists it
  still supplies its layer until the new file for that layer exists, so no setting is dropped. Every
  run prints one warning per old file naming where to move it. A later release removes these reads.
