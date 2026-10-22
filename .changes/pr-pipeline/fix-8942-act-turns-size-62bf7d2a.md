---
bump: patch
---

### Fixed

- The skill-run diagnostics in both run-activity files (`act-turns.json` and the step summary) now fit the 32768-byte carry cap after JSON escaping: each `denied` entry's `tool_name` is cut to 100 characters, the write file keeps at most 4 `local_command_stderr` messages as the read file does, `subtype` and up to 10 model names are cut to 100 characters, and `local_command_stderr_total` counts every stderr message. When the file would still exceed the cap, the oldest stderr messages drop first, then denials from the end, so a PR-mode read run's scan job no longer refuses an oversized file.
