---
bump: patch
---

### Changed

- `setup-apply.mjs` no longer has its own `is a flow map` warning for an object key. The YAML parser already refuses a flow mapping with a parse error, so that warning never printed (#10130).
