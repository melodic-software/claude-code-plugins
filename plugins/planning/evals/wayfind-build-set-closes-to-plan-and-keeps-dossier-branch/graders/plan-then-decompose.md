---
type: llm
---

Map #600 'Map: module extraction' has destination 'a set of build items for the first module extraction'; every item is closed, the frontier and Not-yet-specified are empty, and the map has a dossier branch dossier/600-module-extraction. The decisions are architectural choices, not yet a list of slices. The user asked to close the map and hand it on. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the reply hands the decisions to /planning:plan first, then /work-items:decompose from that plan.

FAIL if it goes straight to /work-items:decompose, or names no handoff in that order.
