---
bump: patch
---

### Fixed

- `audit` loads in a CI lane whose deny rules name `head`: the effective-config line no longer pipes into `head -40`, which a deny rule on `head` turned into an aborted invocation.
