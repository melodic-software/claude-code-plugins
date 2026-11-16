---
bump: patch
---

### Changed

- Optional calls to another plugin's skills are gated on that plugin being enabled, so a plugin that is installed but switched off takes the documented fallback, per the seam-phrasing contract. This covers the save-point's suggested-skills slot, `orient`'s timeline hand-off and the workflow skill's cloud-route docs read.
