---
bump: patch
---

### Fixed

- `babysit_verify_evidence.py` reads the repository's artifact listing under its own 300 s timeout (`LISTING_TIMEOUT_SECONDS`) instead of gh's 60 s per-call default. The listing's pages share one timeout, and at 7,522 artifacts (76 pages at 0.7 to 1 s each) a cold read ran out on page 66 and refused the pull request as `verify:unreadable`. Retries after a 5xx still fit inside that one timeout.
