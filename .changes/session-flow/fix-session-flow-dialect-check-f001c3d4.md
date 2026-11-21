---
bump: minor
---

### Added

- `save_point.py fill` and `amend` write the model's slot values in American spelling: when
  `typos` is on PATH, each finding of `typos --locale en-us` with one correction is applied and
  named on stderr in a `NOTE:` line. Slots that hold the owner's words, commands or a `/goal`
  condition, and quoted text, code, blockquotes and paths in any slot, stay as written. Without
  `typos` the values are written as given.
- The away report gets the same correction each time the Stop hook, `refresh` or `end` rewrites
  it, in its own sections only: the header, the script-owned blocks and quoted text stay as
  written.
- The handoff and step-away instructions tell the model to write in American English and to quote
  the owner's words as given.
