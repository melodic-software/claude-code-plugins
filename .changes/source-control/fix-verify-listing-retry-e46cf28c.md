---
bump: patch
---

### Fixed

- `babysit-prs` pr-merge verdict reader: an artifact listing that timed out, met a network error or got a 5xx is read again, three reads in all with 2s and 4s backoff and a 15s timeout on each retry, before the pull request refuses `verify:unreadable`. Any other failure, a 429, a rate-limit 403, missing credentials and a missing `gh` included, still refuses at once, and a listing that fails every read refuses as before.
