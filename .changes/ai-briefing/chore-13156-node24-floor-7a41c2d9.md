---
bump: major
---

### Changed

- The presentation build now requires Node.js 24 or later: setup's preflight accepts Node.js 24.x and 26.x only, and the build package declares `engines.node >=24`, because unpdf 2.x needs Node.js 24 ([#13156](https://github.com/melodic-software/claude-code-plugins/pull/13156)).
