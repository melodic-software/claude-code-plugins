# machine-health — TODO and approval policy

> **This file holds no state and owns no policy.** Approval state lives at
> `<StateBase>/state/approvals.json` (machine-local, under the plugin data directory). Runtime
> proposals accumulate in `<StateBase>/TODO.md`, not here.

Policy sources of truth — read them there; this file only points:

- **Approvals design, approvable remediation ids, defaults, and the enable/revoke flow** —
  [`references/shared/approvals.md`](references/shared/approvals.md)
- **What is authorized and what is explicitly disabled, with rationale** —
  [`references/windows/remediation-policy.md`](references/windows/remediation-policy.md)
