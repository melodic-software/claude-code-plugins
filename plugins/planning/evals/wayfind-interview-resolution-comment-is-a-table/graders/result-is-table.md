---
type: llm
---

On map #400 'Map: partner API v2', the interview item #402 'Choose the auth scheme' is settled: OAuth client credentials for partners, API keys only for the sandbox, mutual TLS deferred to a later phase, 'partner app' added to the glossary, and the rate-limit item inherits the per-client identity. The user asked to post the resolution and close it. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the resolution comment gives the agreed result as a markdown table.

FAIL if the agreed result is not a table.
