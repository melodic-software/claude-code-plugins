---
bump: minor
---

### Added

- **`/code-metrics:audit size --check` and the `size.check` key.** An opt-in check mode for a
  pre-commit hook or CI step the repository wires itself. `size.check` defaults to `report`, which
  fails nothing; `crossing` fails a changed file whose non-blank lines went from below
  `size.file_lines` at the base to at or above it; `crossing-or-growth` also fails a file already
  over the reference that grew. Exit 1 when a file fails, 2 when the check cannot decide. The
  failure text says to split the file along a real responsibility boundary, never to delete code
  or squash lines, and otherwise to raise the reference or exclude the file with a reason.
