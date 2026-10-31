---
bump: minor
---

### Added

- A Stop hook warns when a turn ends on a changed tree whose recorded `/toolchain:check` or
  `/toolchain:lint` result is not `PASS`, naming the `FAIL`, `INCOMPLETE` or `STOPPED` line, or
  saying no result is recorded for that tree. It reads the record and runs no build, test or lint
  command. A clean tree gets no warning, and neither does a turn that changed no file and
  recorded no result.
- `/toolchain:check` and check-mode `/toolchain:lint` record their Overall line for the tree they
  ran on, through `scripts/record-result.mjs`, unless an ecosystem filter narrowed the run. A
  record counts only for that exact tree, so any later edit voids it, including an unstaged swap
  of a tracked file for a directory or a directory for a file.
- The `turn_end_result_gate` option, read from user or managed settings only: `advisory` (the
  default) warns and blocks nothing, `enforce` also blocks the stop once on a recorded `FAIL`,
  and `off` prints nothing. `enforce` never blocks on `INCOMPLETE`, `STOPPED`, a missing or
  unreadable record, or a missing git.
- A SessionStart notice names `/toolchain:check-prerequisites` when node is not on PATH, since the
  Stop hook launches through node and cannot report its own absence.
