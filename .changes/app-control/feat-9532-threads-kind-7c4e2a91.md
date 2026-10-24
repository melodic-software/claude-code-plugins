---
bump: minor
---

### Added

- `/app-control:drive capture --kind threads` records a stack of every thread for a hung process, with py-spy dump for Python named in the control-skill guidance's hang row; the other runtimes read "not yet". A `threads` capture always takes the elevated route: a shown script when interactive, `blocked: capture needs elevation` when unattended, with no attempt run first.
- Pid binding: the launch step records the launched process's pid, start time and command line in `report.json` (`launch`). Before any command that touches the pid, the shown script included, drive re-reads all three and goes on only when they match; a wrapper resolves to its one child by parent pid, never by a name lookup. A mismatch, a vanished pid, or a wrapper with no child or several is `blocked: launched process no longer matches`. Capture steps record the process's start time.
- An eval case, in the skill's `evals.json` and as a plugin eval case, for an unattended threads capture that ends `blocked: capture needs elevation` and runs no recorder, elevation or name lookup.

### Changed

- `## Next` routes a threads artifact to `/debugging:analyze-profile`.
