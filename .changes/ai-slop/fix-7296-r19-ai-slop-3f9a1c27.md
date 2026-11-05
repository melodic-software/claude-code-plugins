---
bump: patch
---

### Fixed

- `audit` settles whether the run writes a findings file (it examined tracked files) before fetching the detector-findings contract, so an audit of untracked files no longer makes a network fetch it never uses ([#7296](https://github.com/melodic-software/claude-code-plugins/issues/7296)).
