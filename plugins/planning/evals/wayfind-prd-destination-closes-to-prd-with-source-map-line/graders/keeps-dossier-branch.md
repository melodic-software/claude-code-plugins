---
type: llm
---

Map #610 'Map: saved searches' has destination 'a PRD for saved searches on the jobs board'; every item is closed, the frontier and Not-yet-specified are empty, and the map has a dossier branch dossier/610-saved-searches. The user asked to close the map and hand it on. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the reply does not delete the dossier branch when the map closes.

FAIL if it deletes the dossier branch at map close.
