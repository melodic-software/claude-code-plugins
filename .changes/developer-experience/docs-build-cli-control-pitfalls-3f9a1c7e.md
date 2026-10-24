---
bump: patch
---

### Added

- `/developer-experience:build-cli` CLI contract gains five rules for a control CLI: no inherited handles on a started child, one JSON document on `--json` stdout for a composite command, finding the real app process behind a wrapper pid, rejecting bad flags and ids fast, and naming the override mechanism the app honors. Each carries a source pointer, an as-of date and a recheck trigger. A new eval case checks that a review flags a child started with inherited handles.
