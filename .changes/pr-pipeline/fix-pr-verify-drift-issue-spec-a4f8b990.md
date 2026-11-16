---
bump: minor
---

### Changed

- pr-verify takes an issue the upstream-drift workflow filed as the spec of a pull request that
  closes it and only modifies the `docs/upstream` pages pinned to that upstream on main. The spec
  text names only the upstream id and those pages, never the issue's body, and the entry carries
  `source` `upstream-drift`. Every other Bot-written issue still has no spec.
