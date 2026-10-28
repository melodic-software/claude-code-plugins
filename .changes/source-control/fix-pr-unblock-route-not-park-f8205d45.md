---
bump: patch
---

### Changed

- `babysit_risk.REVIEW_FLOOR` (the `enforcement` class of `FLOOR_CLASSES`, which holds a change until a clean security review binds to its head, not for a person) also covers `.github/scripts/pr-unblock/escalation-routes.mjs`, which `clear-escalations.mjs` and `gate-source.mjs` import, and `escalation-routes.json`, the routing table it reads, so the floor still holds every module its scripts load, and the scripts that act on a pr-unblock stop's route (`report-escalation.sh`, `adjudicate-feedback.mjs`, `publish-feedback.mjs`, `apply-patch.mjs`) with every module they import.
