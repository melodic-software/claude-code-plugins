---
bump: patch
---

### Fixed

- **`course-digest` and `video-digest`: the pre-computed dependency block no longer holds brace
  groups**, which Claude Code's shell permission check refuses
  (`Contains brace with quote character (expansion obfuscation)`). Each line is now a plain list:
  the outer group is gone, and each capped version probe repeats its guard before the fallback
  (`command -v ffmpeg >/dev/null 2>&1 && ffmpeg -version 2>/dev/null | head -1 || command -v ffmpeg >/dev/null 2>&1 || echo "MISSING ..."`),
  which renders the same with and without `pipefail`. The block still needs `allowed-tools` grants
  before it loads outside auto mode; its `node -e` lines have no narrow grant, so that stays open.
