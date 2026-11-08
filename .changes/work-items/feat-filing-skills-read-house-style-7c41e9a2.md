---
bump: minor
---

### Changed

- `track add`, `track edit` (on a title change), `decompose` and `triage` read the repository's house style, `issue-tracker.md` in its standards root, before filing or retitling an item, and apply its filing and title rules; with no such file they use a portable default (`reference/issue-house-style.md`). `triage` retitles an open item whose title breaks the house style.
- `reference/issue-conventions.md` no longer prescribes prefixed titles. Umbrella and recurring items take plain titles; the recurring marker still links an item to its schedule row.
