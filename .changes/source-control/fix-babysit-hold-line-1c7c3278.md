---
bump: patch
---

### Fixed

- babysit-prs: the merge gate and the merge-entry hold also treat a PR body line starting `Hold:` (any case) as a human hold on the merge (the `pull-request ready` flip does not stop for it); before, only "do not merge" or "don't merge" in the body held the merge.
