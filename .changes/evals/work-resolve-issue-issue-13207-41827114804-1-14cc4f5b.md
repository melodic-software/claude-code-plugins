---
bump: patch
---

### Fixed

- `plugin-eval`'s validity gate no longer voids a leg when a finished without-arm run's denied
  search names only the plugin that arm lacks, such as `find / -ipath '*markdown-format*'` or
  `grep -rIl biome-format <run home>` in a slash-command case. The denial is a warning; any other
  without-arm denial keeps the existing rules.
