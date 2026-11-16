---
bump: patch
---

### Changed

- Optional calls to another plugin's skills are gated on that plugin being enabled, so a plugin that is installed but switched off takes the documented fallback, per the seam-phrasing contract. `/planning:plan` gates `/discipline:pick-for-the-problem` and `/performance:goal` and names the inline fallback; its `## Next` no longer says the implementation stage runs in the planning session.
