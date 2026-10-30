---
bump: patch
---

### Changed

- `merge.max-verify-fails`: `verify:repeated-fail` clears when a later head passes. It refuses only
  a head that pr-verify failed past the cap. README (Verifier verdict) and the schema description
  say so.
