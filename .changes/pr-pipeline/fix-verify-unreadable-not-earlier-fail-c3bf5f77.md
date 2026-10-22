---
bump: patch
---

### Fixed

- The verifier verdict rules say a failed read of a verify record, run time or diff refuses `verify:unreadable` rather than keeping `verify:earlier-fail`, except a diff GitHub answers with 404, which still keeps it (#9063).
