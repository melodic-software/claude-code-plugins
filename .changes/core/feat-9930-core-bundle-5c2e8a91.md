---
bump: minor
---

### Added

- A dependency-only bundle: installing `core` installs the catalog's default-on plugins, listed as
  unversioned `dependencies` in its manifest. No skills, agents or hooks. `core` is off by default,
  and CI fails when its list differs from the default-on set.
