---
bump: patch
---

### Fixed

- Intake admission no longer refuses a Feature only because its parent carries a `status: needs-decision` the lanes App set when it refused the parent itself (a Size Large, structural or spec-container parent). That label blocks the parent's Features only while a decision is open: a person set it, or the parent's newest refinement asks questions no later listed human's `**Decision recorded.**` comment answers. `needs-human` and `needs-owner-decision` on the parent still block, and a parent read that fails counts as an open decision.
