---
bump: patch
---

### Fixed

- `babysit-prs` pr-merge verdict reader: an artifact listing that got a 5xx or a fast network error is read again, three reads in all with 2s and 4s backoff, every read and wait inside the one gh timeout a single read would get, before the pull request refuses `verify:unreadable`. Any other failure, a timeout, a 429, a rate-limit 403, missing credentials and a missing `gh` included, still refuses at once, and a listing that fails every read refuses as before.
