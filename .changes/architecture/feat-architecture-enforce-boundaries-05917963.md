---
bump: minor
---

### Added

- **`/architecture:enforce-boundaries`.** Sets up a check for each rule in the `## Boundary rules`
  section of the architecture topic doc, using the strongest mechanism the repository supports: a
  boundary the build already enforces, then the repository's own architecture-test tool, then a
  tool researched at run time, then a check in the repository's own convention. It ships no tool
  config. Each rule is proven on its own by an injected violation that must fail the check naming
  the rule, then pass once only those lines are removed; the check is wired into the command that
  already runs the repository's checks, the rest is reported as not wired, and each entry gains
  `Enforced by: <command>`. Every write waits for a yes, a new dependency is always asked, and an
  unattended run stops at the plan. With no rule recorded it writes nothing and names the
  `conventions` and `boundaries` lenses.
- **Boundary rule forms.** The list of recorded forms adds entry-points only and no cycles, with
  what crosses each. The `boundaries` lens reports both as `not checkable from manifests`, except
  a no-cycles rule between projects, and reports an entry carrying `Enforced by:` as already
  enforced.

### Changed

- `/architecture:improve`'s `## Next` names `/architecture:enforce-boundaries` for a recorded
  boundary rule that nothing enforces yet.
