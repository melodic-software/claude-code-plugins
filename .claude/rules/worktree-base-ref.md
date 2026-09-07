---
description: "This repository sets no worktree.baseRef and never adds one back, even when a review says a merge dropped it; read before editing either settings file"
paths:
  - ".claude/settings.json"
  - ".claude/settings.local.json"
---

# No worktree.baseRef in this repository

Claude Code's `worktree.baseRef` setting picks the ref a new worktree branches from. Unset, it
is `fresh`: the repository's default branch as fetched from the remote, so every worktree
starts from the latest `main`. The value `head` branches from the local checkout's HEAD
instead, which spawns worktrees from whatever a session happens to have checked out.

The `head` override is withdrawn and the setting stays absent on purpose. Do not add `worktree`
to either settings file, and do
not "restore" it because a diff against another branch shows it missing: `origin/main` can carry
it for a while after a branch that removed it opens, and a review comment reading that diff
will call the removal a regression. It is not. Before restoring any key a review says a merge
dropped, run `git log -S'"<key>"' -- .claude/settings.json` on the branch and read the commit
that removed it.
