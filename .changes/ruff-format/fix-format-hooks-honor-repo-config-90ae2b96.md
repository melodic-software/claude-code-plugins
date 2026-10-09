---
bump: patch
---

### Fixed

- **No reformat of pre-existing drift.** The safe-fix pass and the format pass each run only when the file was already clean for that pass before the edit, judged by running Ruff on the Write/Edit `tool_response.originalFile` under the repo's own config. A file that drifted from the config is left as written, so a small edit no longer lands as a whole-file rewrite. A new file is fixed and formatted as before.
