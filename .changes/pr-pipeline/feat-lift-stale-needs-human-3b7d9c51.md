---
bump: minor
---

### Added

- `clear-escalations.mjs` lifts more pr-unblock stops once their cause is gone: `workflow-staged` also clears once a trusted move took the head off the resume key and the head contains main as it was at the escalation; the `ci-fix-*` stops other than `ci-fix-protected-path` clear once a trusted move took the head off the resume key and, at the new head, no check but `ci-status` fails, runs or was cancelled and each check's latest run ended `success`, `neutral` or `skipped`. A trusted move is read with the job token from the branch's activity, never from comment text: every push since the label is by a `human` of the base `trusted-actors.json`, matched by id, never the lanes App. Security, intent, decision, protected-path and own-patch stops still wait for a person.
