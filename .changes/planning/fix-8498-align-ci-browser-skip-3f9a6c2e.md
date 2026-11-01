---
bump: patch
---

### Fixed

- `align.test.sh` now fails under `CI=true` when node is missing or when `align.js` skips for want
  of playwright-core or a Chromium, as the UI suites already do, so a CI leg without a browser no
  longer reports the page alignment check green. Local runs still skip green
  ([#8498](https://github.com/melodic-software/claude-code-plugins/issues/8498)).
