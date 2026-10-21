---
bump: patch
---

### Fixed

- **`/plugins` sync reports an `--only-install` id that no marketplace in the run claims** ([#7963](https://github.com/melodic-software/claude-code-plugins/issues/7963)). Before, a mistyped or foreign id was skipped by every marketplace and vanished from the report. It now renders as an `error:` row naming the id, and an id one marketplace claims raises no error from the others.
