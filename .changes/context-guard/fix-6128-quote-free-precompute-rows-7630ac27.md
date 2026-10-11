---
bump: patch
---

### Fixed

- **`setup`: the `zones.json` pre-computed row no longer holds a brace group with quotes**, which
  Claude Code's shell permission check refuses
  (`Contains brace with quote character (expansion obfuscation)`). The row is now an `if` list that
  reads the file with `head -40` directly, rendering the same capped contents or the same
  `(absent)` / `(present but unreadable)` token. The `jq` and `node` probes are pre-approved in
  `allowed-tools`. Outside auto mode the skill still does not load headless: the check refuses a
  read of a file outside the session's working directories, which this row is.
