---
bump: minor
---

### Added

- `scripts/build_capture_script.py`, with `scripts/build_capture_script.test.sh` beside it, builds the shown capture script for `/app-control:drive`. It checks the launch record's pid, uid, start time and command line hash against `/proc` and the caller's uid, resolves a wrapper's one child with `--child`, or binds a pid the person names with `--attach-pid`. It writes the script to a new file and prints each checked process and the script. The script reads `starttime` from the fields after the last `)` of `/proc/<pid>/stat`, rechecks every pid before the recorder and again after it exits, and deletes the capture and exits 3 on a difference. An elevated recorder that writes a `<file>` writes it into a new directory the elevated user makes; the script copies it to the capture path as the user running it, so the captured process cannot redirect the elevated write through a symlink.

### Changed

- `/app-control:drive` runs a pid-bound capture's recorder only through the built script and shows the builder's full output before the yes. A `cpu` or `heap` recorder that takes a pid now gets the same binding and recheck as `threads`. An elevated attach records the attached pid's uid, start time and hash when its script is shown, and the script rechecks them.
- **Breaking on hosts other than Linux:** a `cpu` or `heap` capture whose recorder takes a pid, and an elevated attach, now record `blocked: pid binding covers Linux only, not <platform>` on macOS, Windows and any other host that is not Linux, since the binding reads the Linux process table.

### Fixed

- On macOS and Windows a `threads` capture records `blocked: pid binding covers Linux only, not <platform>`. Before, it was blocked with no reason named. An unattended capture whose launch record holds an invalid pid now records `blocked: launched process no longer matches` before `blocked: capture needs elevation`.
