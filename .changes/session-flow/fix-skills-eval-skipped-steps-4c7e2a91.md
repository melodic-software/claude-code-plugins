---
bump: patch
---

### Fixed

- `continue-in-background` reads an earlier handoff's section by name, following a section moved to the hop file.
- `orient` resolves the handoffs directory from the save-point memory root, never Claude Code's auto-memory directory.
- `find-handoff` treats a waiver in the request as no confirmation and still stops for the operator's yes.
