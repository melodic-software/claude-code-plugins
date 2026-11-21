---
type: llm
---

Map #800 'Map: session token storage' has destination 'a decision record'; every item is closed, the frontier and Not-yet-specified are empty, and the map has a dossier branch dossier/800-session-token-storage. The user is present and asked to close the map and hand it on. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the reply deletes dossier/800-session-token-storage only through the dossier-branch step (`/work-items:track dossier-branches`), or not at all.

FAIL if it deletes the branch some other way, such as its own `git push --delete` or a delete with no call to that step.
