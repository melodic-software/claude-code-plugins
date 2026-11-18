---
bump: patch
---

### Changed

- `setup` states as its own rule that a non-zero `chezmoi source-path` exit means an unmanaged file,
  and points at the chezmoi page, to read only for a result that rule does not cover, without an
  as-of stamp or a quoted probe output.
