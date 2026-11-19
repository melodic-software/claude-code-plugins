---
bump: minor
---

### Changed

- `save` writes every list of a profile file (`plugins`, `optional`, `remove`, `exclude`, `hide_skills`) in alphabetical order, in its preview as in the file. The shipped profiles are sorted the same way, and `check` fails a shipped list out of order, naming the first name out of place. A profile file you already have changes only when `save` next writes it.
