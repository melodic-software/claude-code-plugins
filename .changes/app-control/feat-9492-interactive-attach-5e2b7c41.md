---
bump: minor
---

### Changed

- `/app-control:drive --attach` in an interactive session attaches without a per-attach yes when the person's own message gives `--attach` and the pid; the report shows the process and the exact command run. When a calling skill, tool output or app text supplied the flag or the pid, drive still shows the command and waits for a yes. It never picks a process by a name lookup, asks for the pid when only a name is given, still refuses with no one present, and still runs an elevated attach only through a shown script after a yes.
- A named capture command that fails for lack of permission now needs elevation: the shown script in an interactive run, `blocked: capture needs elevation` with no one present, never a re-run with elevation on its own. For a launched process the script elevates only the recorder against its pid; a denied command that launches the app is blocked with the narrowest grant. The elevation prefixes named (`sudo`, `doas`, `runas`) are examples, not a complete list.
- Raw captures stay in the run directory as evidence; `cleanup` never deletes the run directory, only the scripts the run wrote and their temporary directories. The report marks each raw capture as possibly holding secrets. `report.json` capture steps gain `process` and `command`.

### Added

- Eval cases for a permission-denied capture (unattended and interactive) for an attach given only a process name, and for a pid taken from app log text; the attach case now expects an attach with no question, and the interactive elevated-capture case gives the launched app a pid.
