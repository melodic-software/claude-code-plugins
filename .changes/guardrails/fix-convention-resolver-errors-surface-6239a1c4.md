---
bump: patch
---

### Fixed

- `block-convention-violation` and the `commit-msg-convention` git hook no longer read a failing convention resolver as "no convention tracked". Exit 1 with empty stderr stays quiet; exit 1 with a diagnostic (a non-ERE pattern, a broken `convention_source`) or exit 2 now fails open for that key alone with a notice naming the check that did not run, carrying the resolver's diagnostic: once per session on both channels from the guard, on stderr from the git hook. A key that resolved still enforces, and a failed resolution is not cached.
