---
bump: minor
---

### Changed

- `/app-control:drive --attach` in an interactive session attaches to the process the person named by pid without a per-attach yes, and the report shows the process and the exact command run. It never picks a process by a name lookup, still refuses with no one present, and still runs an elevated attach only through a shown script after a yes.
- A named capture command that fails for lack of permission now needs elevation: the shown script in an interactive run, `blocked: capture needs elevation` with no one present, never a re-run with elevation on its own. The elevation prefixes named (`sudo`, `doas`, `runas`) are examples, not a complete list.
- Raw captures stay in the run directory as evidence; `cleanup` never deletes them, only the scripts and temporary directories the run made. An elevated script writes its capture into the run directory.

### Added

- Eval case for a permission-denied capture under `--unattended`; the attach case now expects an attach with no question, and the interactive elevated-capture case gives the launched app a pid.
