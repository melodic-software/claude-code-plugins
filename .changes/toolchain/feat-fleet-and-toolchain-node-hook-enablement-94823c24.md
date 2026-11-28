---
bump: patch
---

### Changed

- Resolve `result_gate_enabled` in-process in `hooks/result-gate.mjs` via the shared `lib/hook-enabled.mjs` helper instead of spawning `bash` on `hooks/hook-enabled.sh`, removing the vendored shell helper.
