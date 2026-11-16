---
bump: patch
---

### Changed

- Optional calls to another plugin's skills are gated on that plugin being enabled, so a plugin that is installed but switched off takes the documented fallback, per the seam-phrasing contract. `/verification:confirm`'s `## Next` names enabling app-control, installing it first if it is not installed.
