---
bump: minor
---

### Added

- `save_point.py fill` and `amend` write the model's slot values in American spelling: when
  `typos` is on PATH, each finding of `typos --locale en-us` with one correction is applied and
  named on stderr in a `NOTE:` line. Slots that hold the owner's words, commands or a `/goal`
  condition stay as written, and so do quoted text, code spans and blocks, blockquotes, paths,
  flags and snake_case or camelCase identifiers in any slot. Without `typos` the values are
  written as given; `typos` is an optional prerequisite of the handoff and step-away skills.
- The away report gets the same correction each time the Stop hook, `refresh` or `end` rewrites
  it, in its own sections only: the header, the script-owned blocks and quoted text stay as
  written.
