---
bump: patch
---

### Changed

- Optional calls to another plugin's skills are gated on that plugin being enabled, so a plugin that is installed but switched off takes the documented fallback, per the seam-phrasing contract. `ship run` without the implementation plugin tells the user to enable it, installing it first only when it is missing.
