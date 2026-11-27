---
bump: patch
---

### Fixed

- `hygiene.py apply` and `handoff-apply` probe open handles with one `lsof` run per approved candidate, read the mount table once per candidate and reuse the candidate's repository check for every entry, instead of repeating each per captured entry. An entry lsof names, or a directory holding one, is skipped as `locked` while its siblings are removed; an lsof diagnostic or timeout still skips every entry as `handle-state-unverified`, and an open name that maps to no snapshot entry holds the whole candidate.
