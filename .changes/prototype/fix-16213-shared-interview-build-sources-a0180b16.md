---
bump: patch
---

### Changed

- `/prototype:explore-directions` shared-interview placement now covers build sources, scripts and scratch files: they go in `<data_dir>/staging/<run>/`, outside the live build folder, or stay in memory, never in a `mktemp` directory. SKILL.md's "Ephemeral placement" `mktemp` template applies only to the offline mockup.
