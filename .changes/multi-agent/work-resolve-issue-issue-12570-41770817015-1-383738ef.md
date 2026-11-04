---
bump: patch
---

### Fixed

- The `check` line for a missing node no longer prints a literal `<plugin root>` in the registration probe command. It now says to run `bash scripts/check-hook-registration.sh` from the plugin root, the directory passed to `prerequisites.mjs check`, so the command runs as written.
