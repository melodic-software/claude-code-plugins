---
bump: minor
---

### Added

- control-claude-code's launch broker takes `--in-sandbox` and adds it to every launch, ready and log request; a request cannot set it. With it, the driver starts Claude Code without `--restricted`, so Bash is available, and sets no `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB`, because the caller's own sandbox is the boundary and the scrub's nested sandbox cannot start inside it ([#13711](https://github.com/melodic-software/claude-code-plugins/issues/13711)). The driver refuses `--in-sandbox` unless the launch keeps an unattended `ANTHROPIC_API_KEY` starting with `ccd-dummy-`, so a local drive cannot drop `--restricted` or the scrub around a real credential. Launches without the flag are unchanged.
