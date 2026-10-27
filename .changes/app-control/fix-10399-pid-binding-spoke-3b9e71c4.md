---
bump: minor
---

### Added

- `/app-control:drive`'s `report.json` gains `secrets_mark`: one entry per raw capture, and per report file once it holds a command line, with its path, the "may hold secrets; do not commit" mark and whether the run directory sits unignored in a git working tree.

### Changed

- `/app-control:drive`'s Pid binding rules move to the `drive/reference/pid-binding.md` spoke with only their links adjusted; the hub's launch row, `threads` capture row, `threads` rule and cleanup rule link it.

### Removed

- The control-skill contract's manual pointers for dotnet-stack, GDB `thread apply all` and `GOTRACEBACK`, since no `threads` row names those tools. The dotnet-trace and dotnet-gcdump pointers stay.
