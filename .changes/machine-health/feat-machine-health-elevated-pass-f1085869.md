---
bump: minor
---

### Added

- The audit can run an optional elevated pass for the admin-gated checks. The session writes a one-command script under `<StateBase>/logs/`, shows it with its SHA-256 and launch string, and launches it behind UAC only after the owner's own yes in that session, never under `--scheduled` and never from a subagent. The elevated side checks the hash over the bytes it runs, runs only the elevation-matrix checks, and writes only the result file the session pre-created, refusing a reparse point, a non-disk handle or a swapped file. A standard run imports it with `-ElevatedResultPath` only when it was written with an admin token by the same user, replacing its own results per elevation-matrix check and listing them in `latest.json`'s `elevated_checks`; a refused file adds one UNKNOWN `elevated-pass` result. A state or report folder whose path holds a single quote or a control character cannot use the pass.

### Changed

- The non-elevated banner and the report's elevation block now point to the elevated pass instead of printing a transcript-based command to run from an elevated terminal.
