---
bump: patch
---

### Fixed

- `run-validity.py` no longer counts a Bash call whose result says the session has no Bash tool (`No such tool available: Bash`) as Bash that ran. A run offered no Bash whose only Bash calls hit that error is left out of its arm, as a run with no Bash call is, and the `bash ran:` line ends with `, absent tool <n>`, the count of such calls. The eval workflows' `bash ran:` line check accepts the new ending.
