---
bump: patch
---

### Fixed

- `block-dangerous-git` and `block-noncanonical-commit` cap how deep their git alias walk nests, sized to the process's stack, and deny past the cap. A long inline alias chain used to overflow a small stack (512 KB) and crash the guard with exit 139, which Claude Code lets through; it now exits 2 with the alias-chain deny. Without `/proc` (macOS, Git Bash) or with an unlimited stack the cap falls back to 25 levels, and no stack raises it past 409. The test overrides can only lower the cap.
