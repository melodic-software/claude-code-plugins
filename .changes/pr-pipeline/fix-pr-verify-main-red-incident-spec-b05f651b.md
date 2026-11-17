---
bump: minor
---

### Fixed

- pr-verify takes a main-red incident the monitoring lane filed (github-actions[bot] wrote it and
  nobody else last edited it, its title is `Restore the failing required checks on main` and its
  first body line is the `incident:main-red` marker) as the spec of a pull request that closes it
  or names it on a `Refs:` line. The spec is one fixed text, never the issue's body, and the
  entry carries `source` `main-red-incident`; a `Refs:` pull request for it names no remaining
  work. Before, every red-main fix that linked the incident failed with no trusted spec text.
- `.github/scripts/maintenance-monitor-signals/issues.mjs` joins the floor as an `enforcement` row,
  since the resolver now imports its title and marker.
