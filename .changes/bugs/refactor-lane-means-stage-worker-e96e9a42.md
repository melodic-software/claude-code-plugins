---
bump: major
---

### Changed

- **`/bugs:scan` hunts focus areas, not lanes.** "Lane" now means only a worker that serves one
  pipeline stage, so the slice a scan rotates through is a focus area. The flag is `--area <name>`
  (`--lane` is gone, with no alias), the `docs/conventions/bugs.yaml` key is `areas` (rename a
  `lanes:` key to `areas:`), the persisted cursor block writes `area`, `area-index` and
  `area-count`, the scope tag is `in-area` / `out-of-area`, and a filed item's provenance line is
  `Filed by /bugs:scan (area: <name>)`. Rotation reads only the new keys, so the first run after
  upgrading falls through to the date-derived floor until it files or persists under the new names.
  `/bugs:setup` checks and writes `areas`.
