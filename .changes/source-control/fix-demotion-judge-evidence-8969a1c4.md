---
bump: patch
---

### Fixed

- The post-merge demotion judge no longer excuses a suite outside the affected set that failed
  again on a re-run unless it shows non-determinism: it passed on an earlier attempt of the same
  commit, or a full run at the last green commit failed it on some attempt. Otherwise it demotes,
  an open quarantine issue included.
- The judge names a Python leg's failing suites only from the call and exit lines that carry the
  step's nonce, so a pytest summary or call line in a failing test's captured output credits
  nothing to another suite. A Python leg's log with no nonce line, or with a second one, names no
  suite, so the run demotes.
