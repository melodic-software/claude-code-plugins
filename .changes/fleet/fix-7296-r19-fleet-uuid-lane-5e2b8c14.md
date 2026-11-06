---
bump: patch
---

### Fixed

- `/fleet:reach` no longer tells the session to mint a `--session-id` UUID with `uuidgen` or `/proc/sys/kernel/random/uuid`: a handed-over command keeps `<uuid>` for its runner, and a turn the session runs itself resumes with the `session_id` from `--output-format json` ([#7296](https://github.com/melodic-software/claude-code-plugins/issues/7296)).
