---
bump: minor
---

### Changed

- Ecosystem records move to the convention home, `docs/conventions/ecosystems/<ecosystem>.yaml`, with the personal override beside them as `<ecosystem>.local.yaml`. `/toolchain:check` and `/toolchain:lint` read the new home first and the legacy `.claude/ecosystems/` file of a name absent there; with both present the new file wins and the report names both paths. `/toolchain:setup` writes only the new home, warns on each legacy file, and `apply` moves legacy files there (`git mv` for a tracked one). The recommended `.gitignore` line is `docs/conventions/**/*.local.*`.
