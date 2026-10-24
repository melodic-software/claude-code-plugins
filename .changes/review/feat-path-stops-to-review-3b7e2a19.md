---
bump: minor
---

### Changed

- The CI security-review lane (`/review:security-review`) reads the control surfaces the automation lanes now push to with no path refusal with extra scrutiny, and names each one a diff touches with what it lets run, load or merge: the trusted-actor list and trusted-trigger check, `CODEOWNERS`, `.gitmodules`, a plugin's `hooks/` and `bin/`, `.mcp.json`, a `plugin.json` key that runs or loads code, and `AGENTS.md`, `CLAUDE.md` and `.claude/` rules.
