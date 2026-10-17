---
bump: patch
---

### Fixed

- `babysit-prs` pr-merge verdict reader: a transient failure of the artifact listing (no HTTP response, a 5xx, a 429, or a 403 naming a rate limit) is read again, three reads in all with 2s and 4s backoff, before the pull request refuses `verify:unreadable`. Any other failure still refuses at once, and a listing that fails every read refuses as before.
