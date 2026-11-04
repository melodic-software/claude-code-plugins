---
bump: patch
---

### Fixed

- The `check` line for an old Claude Code no longer prints a literal `<plugin root>` in the mods probe command. It now says to run `bash scripts/check-mod-load.sh` from the plugin root, the directory passed to `prerequisites.mjs check`, so the command runs as written.
