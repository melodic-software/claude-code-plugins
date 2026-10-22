---
bump: minor
---

### Added

- The audit can run an optional elevated pass for the admin-gated checks. The session writes a one-command script under `<StateBase>/logs/`, shows it with its SHA-256, and launches it behind UAC only after the owner's yes in that session, never under `--scheduled`. The elevated side checks the hash over the bytes it runs, runs only the elevation-matrix checks, and writes only the result file the session pre-created, refusing a reparse point or a swapped file. A standard run imports it with `-ElevatedResultPath`, replacing its own results per check and listing them in `latest.json`'s `elevated_checks`; a refused file adds one UNKNOWN `elevated-pass` result.

### Changed

- The non-elevated banner and the report's elevation block now point to the elevated pass instead of printing a transcript-based command to run from an elevated terminal.
