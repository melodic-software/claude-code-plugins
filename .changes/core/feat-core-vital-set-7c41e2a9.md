---
bump: minor
---

### Changed

- `core` now installs the vital lifecycle set, from planning through the pull request and session handoff: planning, discovery, verification, toolchain, review, source-control, session-flow and work-items. It no longer installs the whole default-on set. CI now fails when a member is missing from the catalog or is not default-on, in place of requiring the list to equal the default-on set.
