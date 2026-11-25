---
bump: patch
---

### Changed

- Handoff files write history, not the present: each claim about code or state carries the date it was true and, for code, the commit (`owner/repo@<sha>`), and a changed fact is superseded by a new dated claim instead of edited. `validate` warns on a bare "currently" or "now" in Observations with no date or commit.
