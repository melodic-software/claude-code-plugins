---
bump: minor
---

### Added

- `/code-metrics:audit size --check` measures a generated copy at its canonical: the row carries
  the canonical's path and never fails on its own count, while the canonical keeps the rule. A
  file counts as such a copy only when a `scope.registries` cluster line
  (`<canonical> -> <member>...`) names it as a member and the new `size.copies_manifest` file
  lists the `<canonical> <copy>` pair. The key defaults to `null`, which exempts nothing.
