---
bump: minor
---

### Added

- `GUARDRAILS_SESSION_UNWATCHED=1` marks an interactive session that nobody is watching. block-dangerous-git and block-root-delete-target normally ask in an attended session (`CLAUDE_CODE_SESSION_ATTENDED=1`). In a session marked this way they block instead, and the reason names the command for a person to run later, so the session does not wait on a prompt nobody answers. Claude Code tells a hook nothing about whether a person is watching, which is why the session has to declare it. The variable only turns an ask into a block. See the README's "Unwatched sessions" (#12910).
