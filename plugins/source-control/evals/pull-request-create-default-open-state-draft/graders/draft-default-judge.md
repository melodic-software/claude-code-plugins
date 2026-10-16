---
type: llm
---

PASS if every one of these holds:

1. The reply states that the open state resolved to draft.
2. The reply names the default as the level that supplied it, not a repository file, a userConfig value, or a request.
3. Any create command the reply shows or describes opens the PR as a draft.
4. The reply names /source-control:pull-request ready as what flips the draft later, and does not run it in this turn.

FAIL if the reply says the default open state is ready, runs or starts the ready phase on the new PR, or opens the PR ready for review.
