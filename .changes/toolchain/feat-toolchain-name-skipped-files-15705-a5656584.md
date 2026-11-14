---
bump: minor
---

### Changed

- `/toolchain:lint` and `/toolchain:check` name each changed text file outside every ecosystem on an
  `Outside every ecosystem` line below the table, instead of skipping it silently. A binary file
  stays quiet, and the line changes no Status or Overall line.

### Added

- The ratchet's vendored suppression scanner takes `--unread-to <file>`, listing the text files it
  has no kind for; its `--count` output is unchanged.
