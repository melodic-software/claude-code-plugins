---
bump: patch
---

### Changed

- `/source-control:pull-request` monitor states that a delegated fix waits until every check and reviewer on the current head is terminal, then goes out as one brief carrying the head's failing checks, unresolved review threads and verifier failures together, so a late finding does not cost a second round and push.
