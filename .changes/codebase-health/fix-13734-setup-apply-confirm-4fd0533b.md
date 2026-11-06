---
bump: patch
---

### Fixed

- `/codebase-health:setup apply` no longer writes, edits or rewrites `.claude/codebase-health.md` before you confirm the proposed changes. It drafts the config, shows it and asks, and writes only after your reply, whatever tool it would use ([#13734](https://github.com/melodic-software/claude-code-plugins/issues/13734)). The two setup eval cases held out of #8635's conversion, `setup-apply-interviews-first` and `setup-apply-keeps-existing`, are restored.
