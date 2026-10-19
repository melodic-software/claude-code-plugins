---
bump: patch
---

### Fixed

- The jscpd adapter now leaves out a scoped file whose name is not valid UTF-8 and names it, with the bad bytes escaped, in the run's partial-reason line. jscpd 5.x failed the whole run with no report on such a name, and 4.x dropped the file without a message.
