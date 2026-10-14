---
bump: minor
---

### Changed

- All six skill descriptions are shorter and keep their quoted trigger phrases. The `sprite`, `scene`, `ui` and `vfx` bodies are tighter: `sprite` asks for an output location before rendering when none is named, and `vfx` states the native fallback when Aseprite is missing. The `animate` and `tileset` bodies are unchanged.

### Added

- Seven outcome eval cases under `evals/` and frozen trigger-probe sets under `probes/`.
