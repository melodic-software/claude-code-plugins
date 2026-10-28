---
bump: patch
---

### Fixed

- `/source-control:babysit-prs`: the merge policy reads the default branch's head by its full ref (`git/ref/heads/<branch>`) instead of `commits/<branch>`, which takes any commit-ish, so no tag or other ref named like the branch answers for it. `_default_branch_head` names the commit that the default branch's pipeline config, lane adoption's trusted actors and the post-merge floor are read at. The in-flight cap and the shared post-merge answer read the head the same way. An absent ref or a SHA that is not 40 lowercase hex still raises `PolicyReadError`.
