---
bump: minor
---

### Added

- `clear-escalations.mjs` lifts more pr-unblock stops once their cause is gone: `workflow-staged` also clears once a trusted move took the head off the resume key and the head contains main as it was at the escalation; the `ci-fix-*` stops clear once a trusted move took the head off the resume key and no check but `ci-status` fails, runs or was cancelled at the new head; and `unexpected-path-staged` and the `conflict-patch-*` stops clear once GitHub reports the PR mergeable. A trusted move is read with the job token from the branch's activity, never from comment text: every push since the label is by a `human` of the base `trusted-actors.json` or the lanes App's entry, matched by id. Security, intent and decision stops still wait for a person.
