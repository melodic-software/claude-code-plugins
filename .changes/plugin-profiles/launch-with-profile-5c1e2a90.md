---
bump: minor
---

### Added

- `launch [<name>] [--folder <dir>]` writes the one-session file for a folder and profile and prints the `claude` command that starts a session in it, asking nothing and changing no settings file. With no name it takes this session's profile, else the folder's; with neither the command carries no profile. The command always clears an inherited `PLUGIN_PROFILES_SESSION`. `--with` takes a launcher's own settings (a JSON object or a file) and writes one file holding both, since `claude` keeps only the last `--settings`. `--unattended` stops when the profile switches on a plugin missing a required prerequisite. `--json` prints the result with the words a launcher runs before its own arguments. A session file no launch has written for 30 days is removed by the next launch.
- `status` prints the command that starts another session here in the profile in force, which a handoff uses as its restore line.

### Changed

- The one-session file is one per folder and profile, so sessions in two folders with one profile no longer share a file.
