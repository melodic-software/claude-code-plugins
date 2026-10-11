---
bump: minor
---

### Removed

- `/session-flow:orchestrate` no longer tells a session to treat unobservable rate-limit headroom as thin and start fan-out narrow; imperative 7 keeps only "do not invent window percentages" and the backoff on real rate-limit errors (#7135).
