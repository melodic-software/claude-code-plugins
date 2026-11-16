---
bump: patch
---

### Changed

- Optional calls to another plugin's skills are gated on that plugin being enabled, so a plugin that is installed but switched off takes the documented fallback, per the seam-phrasing contract. `/corrections:codify issues` now stops when `work-items` is installed but off instead of calling `/work-items:track`, and both it and `preferences` print `claude plugin enable`, preceded by `claude plugin install` when the plugin is not installed.
