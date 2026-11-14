---
bump: minor
---

### Added

- `/code-metrics:audit-suppressions` names each text file in scope whose language the scanner has
  no kind for: a `Not read` line in the report, an `unread` list in the JSON document, and a
  `Not examined` count in a `--findings` file. A binary file stays quiet.
- The scanner takes `--unread-to <file>` to write those paths; its stdout, `--count` included, is
  unchanged.
