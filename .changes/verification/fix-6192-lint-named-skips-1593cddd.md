---
bump: patch
---

### Fixed

- confirm: the cross-cutting lint step now describes lint's named `skip (tool missing: <tool>)` and `INCOMPLETE` output, and the gate states that a lint-only `INCOMPLETE` run holds the verdict below `CONFIRMED` (#6192).
