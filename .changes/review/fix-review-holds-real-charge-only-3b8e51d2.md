---
bump: minor
---

### Changed

- `/review:security-review` reads the takeover paths (the trusted-actor list, the `check-trusted-trigger`, `check-kill-switch`, `request-lane-token` and `resolve-config` actions, `CODEOWNERS`, `.gitmodules`) with extra scrutiny, rates a change there that lets an account, App or code outside the trusted set gain trust, or weakens one of those checks beyond the linked issue, as CRITICAL, and never skips a change to them.
