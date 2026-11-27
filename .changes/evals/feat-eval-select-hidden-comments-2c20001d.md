---
bump: minor
---

### Changed

- `select` runs nothing for a comment-line deletion the agent under test cannot see: a comment line in a case's `case.yaml`, or a shell comment line outside any heredoc or multi-line quoted string in a script a case's scaffold runs but never copies, prints, globs over or names in any other form, and that never reads its own source. Fixtures, prompts, graders, samples and anything a scaffold copies into the workspace still run their case, and so does any script the static check is unsure of.
- In every shell file, a comment-shaped line inside a multi-line quoted string now counts as content, and a shell file whose quoting does not read cleanly gets no comment-deletion exemption.
