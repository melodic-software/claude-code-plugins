---
type: llm
---

The user asked wayfind to chart the partner-API v2 effort, interviewed earlier. Open questions: auth scheme, rate-limit model, versioning policy; nobody can say what 'partner tiers' should mean. The user gave no destination. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the reply names a destination and asks the user to confirm it before any map issue or decision item is created.

FAIL if it creates the map or items without a confirmed destination, or never asks about the destination.
