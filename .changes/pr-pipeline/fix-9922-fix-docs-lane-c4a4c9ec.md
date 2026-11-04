---
bump: patch
---

### Fixed

- `pr-refine.yml`'s `fix-docs-handoff` and `fix-docs-subscription-handoff` no longer go red when GitHub's jobs listing still leaves a fact unsettled after `handoff-evidence.sh`'s read budget. They set `HANDOFF_EVIDENCE_LAG=notice`, so that lag ends as one notice with empty outputs, which start no later leg. A failed read still fails the job, and every other lane keeps the script's default.
