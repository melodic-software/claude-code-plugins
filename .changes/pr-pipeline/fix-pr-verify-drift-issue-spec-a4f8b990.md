---
bump: minor
---

### Changed

- pr-verify takes an issue the upstream-drift workflow filed as the spec of a pull request that
  closes it and only modifies the `docs/upstream` pages pinned to that upstream on main. The spec
  text names only the upstream id and those pages, never the issue's body, and the entry carries
  `source` `upstream-drift`. Every other Bot-written issue still has no spec.
- `docs/upstream/**` joins the floor as an `enforcement` row and CARRY_REFUSES, since the resolver
  now reads those pages: a pull request touching them holds as `review-path:` until a clean
  security review binds to its head, and a push touching them stops an approval carrying.
