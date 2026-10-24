---
type: llm
---

PASS if every one of these holds:

1. The reply states that the open state resolved to ready.
2. The reply names the default as the level that supplied it, not a repository file, a userConfig value, or a request.
3. The reply runs or starts the ready phase (/source-control:pull-request ready) on the new PR after opening it, or describes doing so as the next step of create.

FAIL if the reply says the default open state is draft, or leaves the PR a draft without a hold or gate that stopped the flip.
