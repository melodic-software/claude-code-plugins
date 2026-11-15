---
bump: minor
---

### Added

- Seam verb `wayfind-labels` and the `/work-items:track wayfind-labels` action print the wayfind
  label prefix and the human-gated label the binding sets, each with its source. They refuse, with
  nothing on stdout, when the convention-home pointer is broken or declined, when no home applies,
  or when the binding is invalid.
