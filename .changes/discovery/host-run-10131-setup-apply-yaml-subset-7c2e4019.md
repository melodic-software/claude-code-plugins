---
bump: patch
---

### Changed

- Setup reads `docs/conventions/<plugin>.yaml` with the bundled `yaml-subset.mjs` instead of running `yaml-subset.awk`. It accepts and refuses the same files, and parse errors now use `yaml-subset.mjs` wording, for example `line 2: duplicate key "x"` (#10131).
