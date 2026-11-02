---
bump: patch
---

### Changed

- Shared `publish-gate.mjs` synced: the R2 key pair pattern now finds a 32-hex and a 64-hex word on one line in time linear in the line, so a large one-line JSON file no longer takes minutes to scan. It matches exactly what it matched before.
