---
bump: minor
---

### Added

- `find` now scans for capabilities that are built but never wired up on every run, before it
  proposes a new build: exports or imports nothing calls, tables or other stores written but never
  read, and flags that are off and are the only way to reach an existing route
  (`skills/find/context/disconnected.md`). Wiring up an existing capability ranks ahead of a plan
  to build the same capability new
  ([#11728](https://github.com/melodic-software/claude-code-plugins/issues/11728)).

### Changed

- When asked to go straight to implementation, `find` writes the ranked list in its reply before
  it hands the pick to a pipeline skill.
