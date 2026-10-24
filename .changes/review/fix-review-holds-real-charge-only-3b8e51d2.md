---
bump: minor
---

### Changed

- `/review:code-review` returns a `cost` hold only for a real charge, as the review wrapper's prompt defines it. A change that only spends prepaid credits or subscription usage is neither a hold nor a finding: the summary names what it spends in one line.
- Neither review skill returns a `trust-gate` hold. A changed path alone holds nothing: `/review:security-review` reads the takeover paths (the trusted-actor list, the `check-trusted-trigger`, `check-kill-switch`, `request-lane-token` and `resolve-config` actions, `CODEOWNERS`, `.gitmodules`) with extra scrutiny, rates a change there that lets an account, App or code outside the trusted set gain trust, or weakens one of those checks beyond the linked issue, as CRITICAL (which holds as `critical-security`), and never skips a change to them.
