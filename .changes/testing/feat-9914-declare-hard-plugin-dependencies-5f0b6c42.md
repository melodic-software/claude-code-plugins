---
bump: minor
---

### Changed

- **`testing` declares `mutation-testing` as a dependency.** The `/testing:cleanup` mutation gate runs through `/mutation-testing:audit`, and without that plugin only `--cannot-fail-only` runs, so the manifest's `dependencies` now lists `mutation-testing`, and installing `testing` installs it.
