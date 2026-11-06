---
bump: minor
---

### Added

- control-claude-code's launch broker takes `--in-sandbox` and adds it to every launch, ready and log request; a request cannot set it. With it, the driver starts Claude Code without `--restricted`, so Bash is available, and sets no `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB`, because the caller's own sandbox is the boundary and the scrub's nested sandbox cannot start inside it ([#13711](https://github.com/melodic-software/claude-code-plugins/issues/13711)). Launches without the flag are unchanged.
