---
bump: patch
---

### Changed

- The verifier's resolver (`resolve-pr.mjs`) reads the upstream run's jobs for its draft-run check only once a run would otherwise be judged or rated, so a head it skips as already judged or already rated spends one GitHub API call fewer. Every judge and skip decision is unchanged; a draft-started run at a head that already has a counted verdict now reports `already-judged` instead of `draft-run`, and skips either way.
