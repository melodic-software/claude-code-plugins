---
type: llm
---

PASS if every one of these holds:

1. The reply states that the open state resolved to ready.
2. The reply names the default as the level that supplied it, not a repository file, a userConfig value, or a request.
3. The reply says the PR is taken, or would be taken, through /source-control:pull-request ready (Phase 2.5: base merge, reviews, verify gate) to reach ready, rather than staying a draft.

FAIL if the reply says the default open state is draft, says the PR stays a draft with no request for one, or says the PR opens ready for review without going through the ready phase's gates.
