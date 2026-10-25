---
bump: patch
---

### Fixed

- `enable-auto-merge` no longer arms, and disarms, a lanes App pull request whose linked issue carries a label naming untrusted work, in any spelling, or had one removed by a non-human. report-outcome already writes a `Hold:` line when the issue carries the exact label at PR open, so this covers a label added after the pull request opened, or any other spelling. The refusal is one a person clears: the pull request gets the refusal comment and the human-gated label.
