---
bump: patch
---

### Fixed

- `/source-control:babysit-prs`: a `gh api` read that GitHub answers with any HTTP 500 to 599 status is sent again, at most 3 attempts in all and at most 10 retries a process, after a full-jitter wait of up to 4 s and then up to 8 s inside the call's one timeout, so a single 5xx no longer costs the merge lane a whole sweep. Every attempt passes the rate-limit guards and is counted. A write, a rate limit, any other status, a read whose response headers are not read (a `gh` subcommand or the artifact download), an answer carrying `Retry-After` and a read the artifact listing or the `legacy-fails` pacer already paces or repeats itself are sent once, as before.
