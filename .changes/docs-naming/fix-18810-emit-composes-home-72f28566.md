---
bump: patch
---

### Fixed

- **`audit-file-names` composes the plan's home in the emitter.** The skill had the model build the plan path by hand, so a run's trace never showed where the path came from. With no `--out`, `emit-findings.sh` now composes `<memory root>/docs-hygiene/<branch slug>/file-names.md` itself (memory root `.work` unless `--memory-root` names another) and prints it on a `home` line.
