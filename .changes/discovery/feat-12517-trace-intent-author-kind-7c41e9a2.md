---
bump: minor
---

### Added

- `/discovery:trace-intent` sources record `author_kind: owner-quote | agent-relay`, who wrote the words rather than whose login posted them, and `check-author-kind.py` rejects a `Direct` claim with no `owner-quote` source. The intent tracer runs it before hand-back and the parent re-runs it in the acceptance gate. `/discovery:setup check` prints its two allow rules, so paste the twelve rules it prints (#12517).
