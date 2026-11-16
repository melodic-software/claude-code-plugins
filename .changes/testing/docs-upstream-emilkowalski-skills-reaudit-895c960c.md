---
bump: patch
---

### Fixed

- The `worst-case` initials fix skips a generational suffix, so `Christopher Alexander Montgomery III` no longer still yields `CI`, and a field with no limit is reported as "no limit found", which says what the search showed.
