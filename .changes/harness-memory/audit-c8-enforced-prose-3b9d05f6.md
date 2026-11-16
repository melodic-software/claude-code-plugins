---
bump: minor
---

### Changed

- `audit`: C8 flags a CLAUDE.md instruction a deterministic check already enforces for deletion, naming the check, and holds an instruction matching a protected class in the instruction exception register. The cross-file pass that detects already-enforced instructions now reports them under C8.
