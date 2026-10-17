---
bump: minor
---

### Added

- Git-hook drift notices honor a decline key at any git config scope: `decline --global` declines an entry in every clone, `checks.git-hooks.declined` set true declines every entry of every plugin, and an entry's own key set to `false` in a clone opts it back in.
