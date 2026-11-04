---
bump: patch
---

### Changed

- `limits.fix-docs-per-run` accepts 0, which turns CI `fix-docs` off: the dispatcher logs
  `fix-docs is off (fix-docs-per-run: 0)`, sends nothing and makes no GitHub call for it. This
  repository sets 0, the owner's decision in #7576 (D100, Q158); set 1 or more to turn it back on.
