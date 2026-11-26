---
bump: minor
---

### Changed

- The ask-or-deny choice in block-dangerous-git, block-root-delete-target and settings-write-ask reads attendance from one predicate shared with session-flow (`hooks/session-attended.sh`, `hooks/session-attended.mjs`, the variables named in `hooks/session-attended.env`). A session is attended when `CLAUDE_CODE_SESSION_ATTENDED` is `1` and `CLAUDE_CODE_ENTRYPOINT` is not an Agent SDK value, so a session started through the Agent SDK now gets a deny where it got an ask. A missing or unreadable predicate copy denies. `GUARDRAILS_SESSION_UNWATCHED=1` still turns an ask into a deny after the predicate.
