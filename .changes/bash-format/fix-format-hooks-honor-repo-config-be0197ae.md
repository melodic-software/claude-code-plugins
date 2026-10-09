---
bump: patch
---

### Fixed

- **No reformat of pre-existing drift.** shfmt now runs only when the file was already shfmt-clean under the repo's `.editorconfig` before the edit, judged from the Write/Edit `tool_response.originalFile`. A file that drifted from the repo's style (for example, flush-left `case` arms after `switch_case_indent = true` was added) is left as written, so a small edit no longer lands as a whole-file reformat. A new file is formatted as before.
