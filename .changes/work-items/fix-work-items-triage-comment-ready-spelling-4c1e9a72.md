---
bump: patch
---

### Fixed

- `/work-items:triage` spells the ready status `status: ready`, the label the tracker carries, in the skill and its evals; `status:ready` named no label.
- `/work-items:triage` posts one triage comment beside each brief, in the shape the intake lane's comment uses: `Blast radius:` and `Reversible:` lines, numbered open questions each with a `RECOMMENDED:` answer and its basis, and the `**Decision recorded.**` reply line. For a bug it adds the version the reporter ran and the reproduction, run through `/app-control:drive` when the repository has a control skill and the `app-control` plugin is enabled.
- The role-label rule in the triage outcome reference is titled by what it checks, the item author's trust, not by work classes.
