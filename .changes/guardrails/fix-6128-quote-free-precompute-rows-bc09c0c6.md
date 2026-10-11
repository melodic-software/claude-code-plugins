---
bump: patch
---

### Fixed

- **The setup and check skills load under `claude -p` again.** Each pre-computed tool probe was a brace group
  holding a quoted fallback (`{ command -v jq 2>/dev/null || echo "absent"; }`), which Claude Code's
  shell permission check refuses (`Contains brace with quote character (expansion obfuscation)`).
  Outside auto mode that aborts the whole skill with no output and exit 0. The rows are now
  `command -v <tool> 2>/dev/null || echo absent`, which render the same value, and each `command -v`
  probe is pre-approved in the skill's `allowed-tools`, without which the render still aborts in
  default permission mode. Probed headless on Claude Code 2.1.296.
