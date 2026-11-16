---
bump: minor
---

### Added

- `launch [<name>] [--folder <dir>]` writes the one-session file for a folder and profile and prints the `claude` command that starts a session in it, asking nothing and changing no settings file. With no name it takes this session's profile, else the folder's; with neither the command carries no profile. The command always clears an inherited `PLUGIN_PROFILES_SESSION`. `--with` takes a launcher's own settings (a JSON object or a file) and writes one file holding both, since `claude` keeps only the last `--settings`. `--unattended` stops when the profile switches on a plugin missing a required prerequisite. `--dry-run` does every check and prints the result but writes no file. `--json` prints the result with the words a launcher runs before its own arguments. An empty `PLUGIN_PROFILES_SESSION` counts as unset everywhere it is read. A session file no launch has written for 30 days is removed by the next launch. Launch works from any surface, since the session it starts is a CLI session, and each session file sets `PLUGIN_PROFILES_SESSION_FILE` to its own path, so `status` names the file a session was started with, merged or not.
- `/plugin-profile`'s confirmation names the other live sessions in the folder (from `claude agents`), which get the new profile at their next reload or start, and says to start one with the launch command to give it its own. It still applies on Apply. `apply --dry-run --json` carries them as `othersInFolder`.
- `status` prints the command that starts another session here in the profile in force, which a handoff uses as its restore line.

### Changed

- The one-session file is one per folder and profile, so sessions in two folders with one profile no longer share a file.
