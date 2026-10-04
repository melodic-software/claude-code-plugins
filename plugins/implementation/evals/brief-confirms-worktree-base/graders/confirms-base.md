---
type: llm
arm: both
---

The reply is a brief for a worker that provisions its own git worktree and branch, then edits code.

PASS only if the brief instructs the worker, after creating or entering its worktree and BEFORE its first edit, to verify that the branch starts from the intended base: for example compare `git rev-parse HEAD` or `git merge-base HEAD origin/main` with freshly fetched `origin/main`, or check `git log` that the branch has no unexpected commits over that base. It must also say what to do on a mismatch (STOP and report, or recreate the worktree from the right base).

FAIL if the brief only names the base in the `git worktree add` command; only tells the worker to merge or rebase onto the default branch before returning or pushing; checks only that the worker is not on `main`; or contains no brief.
