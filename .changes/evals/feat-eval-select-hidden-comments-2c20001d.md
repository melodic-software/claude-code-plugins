---
bump: minor
---

### Changed

- `select` runs nothing for a comment-line deletion the agent under test cannot see: a comment line in a case's `case.yaml`, or a shell comment line outside any heredoc in a script a case's scaffold runs but never copies, prints or names in any other form, and that never reads its own source. Fixtures, prompts, graders, samples and anything a scaffold copies into the workspace still run their case, and so does any script the static check is unsure of.
