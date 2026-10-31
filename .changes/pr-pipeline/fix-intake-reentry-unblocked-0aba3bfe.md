---
bump: patch
---

### Fixed

- An issue parked at `status: confirmed` no longer gets `agent-ready` from work-unblock when its last blocker closes: that path never checked for `status: ready`, so a parked issue skipped admission. When a blocker closes after admission parked the issue, the lanes App now removes `status: confirmed`, once per close, and `intake-reenter` adds `needs-triage` and dispatches intake. An issue whose milestone is in the new `cordoned-milestones` list in `admission-rules.json` (`After zero`), whose author intake does not admit, that carries a refuse label, or that admission did not park stays where it is. Until a trusted `status: ready` follows that removal, work-unblock does not label the issue. `intake-reenter` ignores every other App removal of that label.
- A hold now replaces a parked `status: confirmed` instead of landing beside it. A refinement with open questions, a held verdict and a refusal for a person each take `status: confirmed` off after adding the hold, so one status stands and a listed human lifting `needs-human` re-enters the issue.
