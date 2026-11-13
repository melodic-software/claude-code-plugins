---
type: llm
---

The user approved a map for a notification-vendor effort and asked for one prototype item: check that vendor Knock can send a templated email and an in-app message from one API call, falling back to Courier if it cannot. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the prototype item body states what the prototype must prove (one API call sends both a templated email and an in-app message).

FAIL if the body does not state what must be proven.
