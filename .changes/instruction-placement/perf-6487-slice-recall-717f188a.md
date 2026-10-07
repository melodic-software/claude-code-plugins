---
bump: patch
---

### Changed

- **The docs lookup procedure checks every part of the question against the sections it read
  before answering ([#6487](https://github.com/melodic-software/claude-code-plugins/issues/6487)).**
  Step 3 of `reference/docs-lookup-procedure.md`, synced from the shared copy, now has the reader
  slice the sections for any part of the question none of its slices covers, and the section of
  every item when the question asks the same thing for each of many events, options or keys.
