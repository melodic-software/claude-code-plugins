---
bump: patch
---

### Fixed

- `/session-flow:audit-friction`'s `mine` output adds `stop_hook_wait_ms`, the time the person waits: the slowest Stop hook per stop, summed over stops. It sits next to `stop_hook_ms`, the sum of every hook's duration. Matching Stop hooks run in parallel, so that sum overstated the wait. The markdown report opens its Stop-hook line with the wait and labels the sum as parallel hook time.
