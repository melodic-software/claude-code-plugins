---
bump: minor
---

### Changed

- **`planning` declares `work-items` as a dependency.** `/planning:wayfind` cannot read or write its decision map without the `work-items` tracker actions, so the manifest's `dependencies` now lists `work-items`, and installing `planning` installs it.
