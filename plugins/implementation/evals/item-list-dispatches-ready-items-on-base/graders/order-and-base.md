---
type: llm
arm: both
---

The reply plans a dispatch of three work items from a list with no PLAN.md and prints one worker brief.

PASS only if all of these hold:

- The first wave dispatches acme/billing#41 and acme/billing#43 together, and holds acme/billing#42 because it has an open blocker (#41).
- The brief for #41 tells the worker, after provisioning its worktree and before its first edit, to confirm that the branch starts from `origin/integration/rounding` (for example that `git merge-base HEAD origin/integration/rounding` equals `origin/integration/rounding`), and to STOP and report on a mismatch.

FAIL if the reply asks for or waits on a PLAN.md; dispatches #42 in the first wave; runs the items one at a time in list order so #43 waits behind #42; checks the base against `origin/main` or the default branch instead of `origin/integration/rounding`; only names the base in the `git worktree add` command without checking it before the first edit; or prints no brief.
