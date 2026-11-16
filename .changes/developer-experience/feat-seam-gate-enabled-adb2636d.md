---
bump: patch
---

### Changed

- Optional calls to another plugin's skills are gated on that plugin being enabled, so a plugin that is installed but switched off takes the documented fallback, per the seam-phrasing contract. The fallback says the plugin is not enabled and prints `claude plugin enable`, with `claude plugin install` first only when it is not installed.
