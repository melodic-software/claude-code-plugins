---
bump: minor
---

### Changed

- **`mutation-testing` declares `testing` as a dependency.** `/mutation-testing:audit --exercised` finds the test files through `/testing:audit --file` and refuses without the `testing` plugin, so the manifest's `dependencies` now lists `testing`, and installing `mutation-testing` installs it.
