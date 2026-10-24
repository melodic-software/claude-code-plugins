---
bump: minor
---

### Changed

- `/review:code-review` returns a `cost` hold only for a real charge: a runner that is not free, or a resource added or resized in infrastructure as code. Spend inside a subscription or prepaid plan (a new model call or agent run, a raised model, effort, turn or timeout limit, a new schedule) is a normal finding naming the spend.
- Neither review skill returns a `trust-gate` hold. A changed path alone holds nothing: `/review:security-review` reads the takeover paths (the trusted-actor list, the `check-trusted-trigger`, `check-kill-switch`, `request-lane-token` and `resolve-config` actions, `CODEOWNERS`, `.gitmodules`) with extra scrutiny, rates a change there that lets an account, App or code outside the trusted set gain trust, or weakens one of those checks beyond the linked issue, as CRITICAL (which holds as `critical-security`), and never skips a change to them.
