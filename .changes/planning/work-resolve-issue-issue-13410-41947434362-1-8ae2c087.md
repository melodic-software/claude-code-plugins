---
bump: minor
---

### Added

- A plan can show which code a phase changes in a `shape` fence anchored by path and symbol (`shape <path>[#<symbol>][ L<n>]`). The citation gate checks each outermost shape anchor at the checked commit. It fails an anchor whose path is missing, whose symbol is not found, or whose line is past the file's end, and warns when the named line lacks the symbol (#13410).
