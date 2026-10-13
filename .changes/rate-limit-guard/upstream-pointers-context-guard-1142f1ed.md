---
bump: patch
---

### Fixed

- The README, reader contract and StopFailure hook comments no longer say Claude Code ignores all StopFailure output; they keep the hook side-effect-only as our decision and point at the live hooks section.

### Changed

- Upstream specifics the docs own (the mods version floor, what turns mods off, which auth exposes subscription windows, the manifest's `experimental` field, the `disable-model-invocation` field text, how Claude Code handles a bad option value) are replaced by anchored pointer records dated 2026-10-11. `/rate-limit-guard:check` takes the floor from `prerequisites.json`.
