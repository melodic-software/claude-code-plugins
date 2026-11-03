---
bump: patch
---

### Changed

- The `audit` skill no longer names which tools write mutants in tree; it reads the configured tool's `tooling.md` row and points at StrykerJS's `inPlace` option.
