---
bump: patch
---

### Fixed

- `pr-refine.yml`'s `fix-docs-handoff` and `fix-docs-subscription-handoff` no longer go red when GitHub's jobs listing still leaves a fact unsettled after `handoff-evidence.sh`'s read budget. They set `HANDOFF_EVIDENCE_LAG=notice`, so that lag ends as one notice with no handoff fact set, which starts no later leg; `fix-docs-handoff` still sets `fallback-ready`, which starts nothing without `handed-off`. A read that failed, a listing that did not parse, a usage error or a missing environment variable still fails the job, and every other lane keeps the script's default.
