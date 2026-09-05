---
description: "This repository sets no worktree.baseRef; new worktrees branch from the remote default branch (Claude Code's default). Never add worktree.baseRef: head back, even when a reviewer says a merge dropped it"
paths:
  - ".claude/settings.json"
  - ".claude/settings.local.json"
---

# No worktree.baseRef in this repository

Claude Code's `worktree.baseRef` setting picks the ref a new worktree branches from. Unset, it
is `fresh`: the repository's default branch as fetched from the remote, so every worktree
starts from the latest `main`. The value `head` branches from the local checkout's HEAD
instead, which spawns worktrees from whatever a session happens to have checked out.

The operator withdrew the `head` override on 2026-09-02 (topic-docs convention 3.1.0, in
[`docs/conventions/topic-docs/CHANGELOG.md`](../../docs/conventions/topic-docs/CHANGELOG.md)),
and the setting stays absent on purpose. Do not add `worktree` to either settings file, and do
not "restore" it because a diff against another branch shows it missing: `origin/main` can carry
it for a while after a branch that removed it opens, and a review comment reading that diff
will call the removal a regression. It is not. Before restoring any key a review says a merge
dropped, run `git log -S'"<key>"' -- .claude/settings.json` on the branch and read the commit
that removed it.
