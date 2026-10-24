---
bump: minor
---

### Added

- `/app-control:drive capture --kind threads` records a stack of every thread for a hung process, with py-spy dump for Python named in the control-skill guidance's hang row; the other runtimes read "not yet". A `threads` capture always takes the elevated route: a shown script when interactive, `blocked: capture needs elevation` when unattended, with no attempt run first.
- Pid binding: the launch step records the launched process's pid, owner uid, start time (in the raw form the recheck reads) and command line in `report.json` (`launch`). The record is data: only a positive integer pid enters a command. Before any command that touches the pid, drive re-reads the values, goes on only when all match exactly and the uid is the invoking user's, and the shown script repeats that recheck as its first lines before its one recorder command; the yes is asked with the pid's command line and start time shown. A wrapper resolves to its one child by parent pid, never by a name lookup. A mismatch, a vanished pid, or a wrapper with no child or several is `blocked: launched process no longer matches`. Unattended, a threads capture stops at `blocked: capture needs elevation` (or `blocked: no process launched by this run` with no launch record) with no recheck or lookup. Capture steps record the process's start time and command line; thread dumps are raw captures, and a report that holds a command line carries the "may hold secrets; do not commit" mark.
- An eval case, in the skill's `evals.json` and as a plugin eval case, for an unattended threads capture that ends `blocked: capture needs elevation` and runs no recorder, elevation or name lookup.

### Changed

- `## Next` routes a threads artifact to `/debugging:analyze-profile`.
