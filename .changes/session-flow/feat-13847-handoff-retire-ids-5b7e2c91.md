---
bump: minor
---

### Changed

- `save_point.py validate` lets a shape-3 hot file retire a predecessor goal amendment or Direction-changes line: each one stays in order or is listed verbatim in this hop's file under `## Retired goal amendments` / `## Retired direction changes`, followed by a `Retired: <reason>` line. The goal quote, intent, vision and opening ask still stay byte for byte. A reason `codified in [R<n>]` fails when `[R<n>]` is not in the hot file (#13847).
