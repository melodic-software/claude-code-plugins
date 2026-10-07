---
bump: patch
---

### Fixed

- **The interview skill's substitution record cites the live manifest reference
  ([#6523](https://github.com/melodic-software/claude-code-plugins/issues/6523)).** It now points at
  `plugins/manifest-reference` ("Reference a saved value" and "User configuration") in place of the
  retired `plugins-reference` page, as of 2026-10-07. The Action Router section pin in
  `interview-defenses.test.sh` moves with it; the `lock` row is unchanged.
