---
bump: minor
---

### Changed

- `/toolchain:lint` and `/toolchain:check` name each changed text file no ecosystem's globs claim,
  instead of skipping it silently; cross-cutting's `**` is never a claim by itself. Lint puts such a
  file on `No ecosystem linter (cross-cutting text checks only)` when cross-cutting ran, and on
  `Outside every ecosystem` when it did not; check, which never runs cross-cutting, uses only the
  second line. A binary or deleted file is not named, and neither line changes a Status or the
  Overall line.
