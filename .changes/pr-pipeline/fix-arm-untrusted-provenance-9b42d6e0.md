---
bump: patch
---

### Fixed

- `enable-auto-merge` no longer arms, and disarms, a lanes App pull request whose linked issue carries a label naming untrusted work, in any spelling, or had one removed by a non-human. This includes a label added after admission while the lane built. The refusal is one a person clears: the pull request gets the refusal comment and the human-gated label.
