---
bump: patch
---

### Fixed

- `/toolchain:lint` reports a missing tool as `skip (tool missing: <tool>)` and reads `INCOMPLETE` when nothing failed but an environment skip remains, matching `/toolchain:check`, so `/verification:confirm` no longer reaches `CONFIRMED` on a lint-only environment gap (#6192).
