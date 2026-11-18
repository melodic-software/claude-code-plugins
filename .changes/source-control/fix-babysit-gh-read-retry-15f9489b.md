---
bump: patch
---

### Fixed

- `/source-control:babysit-prs`: a read that GitHub answers with HTTP 502, 503 or 504 is sent again, at most 3 attempts in all, after a full-jitter wait of up to 4 s and then up to 8 s inside the call's one timeout, so a single 5xx no longer costs the merge lane a whole sweep. Every attempt passes the rate-limit guards and is counted. A write, a rate limit, any other status and a read the artifact listing already repeats itself are sent once, as before.
