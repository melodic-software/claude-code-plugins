---
bump: patch
---

### Fixed

- skill-authoring: resynced the vendored upstream baseline, clearing the scheduled drift check. The update script now strips upstream's self-update block (an instruction to curl an install into `~/.claude/skills/`) on every sync and compares after the same strip, records `metadata.upstream-sha` for the vendored file, and its tests fail if any fetch-and-run or self-update instruction reaches `vendor/`.
