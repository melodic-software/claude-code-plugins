---
bump: patch
---

### Fixed

- `/harness-config:audit-permission-grants` no longer audits `allowed-tools` in a nested `.claude/skills/<name>/SKILL.md` inside the user plugins directory (`${CLAUDE_CONFIG_DIR:-~/.claude}/plugins/`), which Claude Code 2.1.321 stopped loading. It counts them as excluded, non-loadable files. A plugin's own `skills/<name>/SKILL.md` there is still audited.
