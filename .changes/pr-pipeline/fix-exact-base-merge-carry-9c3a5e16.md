---
bump: patch
---

### Fixed

- `ci-status` and `enable-auto-merge` carry a trusted person's hold-path approval over a base merge in two more cases (`merge-holds.mjs` `liftersOf`). An approval GitHub dismissed as stale on the merge's push counts, bound to its own commit and only through the carry (`autoDismissed`: a `review_dismissed` timeline event with no message, a Bot actor and a dismissal commit the merges pushed); a dismissal with a message, by a person, or by a person's push revokes it. When the base changed a file the pull request also changes, the approval carries when the merges brought exactly the base's changes (`exactBaseCarry`, `approvalCarry`): the compare from the approved head to the current head equals, file for file, the compare between the two merge bases. A merge that writes anything of its own carries nothing, and a list of 300 files or more fails closed. The cost-decision carry is unchanged.
