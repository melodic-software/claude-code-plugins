---
bump: patch
---

### Changed

- Optional calls to another plugin's skills are gated on that plugin being enabled, so a plugin that is installed but switched off takes the documented fallback, per the seam-phrasing contract. `/knowledge:course-digest` gates the browser-tool rubric `/testing:run-e2e` owns and names its fallback.
