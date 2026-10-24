---
bump: minor
---

### Added

- `/app-control:drive capture --kind threads` records a stack of every thread for a hung process, with py-spy dump for Python named in the control-skill guidance's hang row; the other runtimes read "not yet". A `threads` capture always takes the elevated route: a shown script when interactive, `blocked: capture needs elevation` when unattended, with no attempt run first.
- Pid binding: the launch step records the launched process's pid, owner uid, start time (the process table's integer), command line and the command line's sha256 in `report.json` (`launch`). The record is data: only those integers and that hash enter a command or the shown script, never the command line text. Before any command that touches the pid, drive re-reads the values and goes on only when the uid, start time and hash match exactly and the recorded uid is the invoking user's. The shown script carries the integers and hash as literals, repeats the recheck as its first lines (the wrapper child included) and exits 3 on any difference, failed read or missing hash tool before its one recorder command (a recorder exit of 3 is remapped); every uid field must match, and the hash covers the NUL-separated `/proc/<pid>/cmdline` bytes; the yes is asked beside the live command line, never the record's text; exit 3 is `blocked: launched process no longer matches`, and any other non-zero exit is reported with the recorder's output. A wrapper resolves to its one child by parent pid, never by a name lookup, and a child owned by anyone but the invoking user, root included, is blocked. Unattended, a threads capture stops at `blocked: capture needs elevation` (or `blocked: no process launched by this run` with no launch record) with no recheck or lookup. Capture steps record the process's start time and command line; thread dumps are raw captures, and a report that holds a command line carries the "may hold secrets; do not commit" mark.
- An eval case, in the skill's `evals.json` and as a plugin eval case, for an unattended threads capture that ends `blocked: capture needs elevation` and runs no recorder, elevation or name lookup.

### Changed

- `## Next` routes a threads artifact to `/debugging:analyze-profile`.
