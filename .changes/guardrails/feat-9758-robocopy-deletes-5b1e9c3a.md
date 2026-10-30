---
bump: minor
---

### Added

- `block-root-delete-target` judges robocopy deletes the way it judges a recursive `rm`, from the Bash and the PowerShell tool (`cmd /c robocopy` included). With `/MIR` or `/PURGE` the destination, the second operand, is a target; with `/MOVE` or `/MOV` the source, the first, is. So `robocopy src / /MIR`, a move out of `$HOME` and a mirror outside the allowed roots are refused, and one strictly inside the git toplevel, the scratchpad or an allowed root passes.
