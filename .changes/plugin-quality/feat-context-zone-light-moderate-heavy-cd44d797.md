---
bump: minor
---

### Changed

- The context-zone rows of the audit's dispatch table and the setup check use the renamed zones:
  `light`, `moderate` and `heavy` (formerly `smart`, `acceptable` and `dumb`). The bundled resolver
  prints the new words and reads old `zones.json` key names for one release.
