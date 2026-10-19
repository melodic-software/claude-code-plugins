---
bump: patch
---

### Fixed

- `/planning:setup --check` and `apply` no longer stop with "Cannot read properties of undefined" on a repository file that sets `shared_session`; they check its nested keys against the schema, and validate string settings by their `minLength`, `maxLength` and `pattern`.
