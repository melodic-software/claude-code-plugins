---
bump: patch
---

### Fixed

- write a minor bump for a breaking change on a 0.x plugin

  write-changelog-fragments.sh mapped a `!` subject or a BREAKING CHANGE
  footer to `bump: major` whatever the plugin's version, so the release
  script took a 0.x plugin straight to 1.0.0. A breaking change to a
  plugin at 0.x now writes `bump: minor` with the entry led by
  **Breaking:**; at 1.0 or above it stays major. `--level major` still
  releases 1.0.0 deliberately.
