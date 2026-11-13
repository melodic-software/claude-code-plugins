---
type: llm
---

The user asked wayfind to chart an invoice-export effort from an interview ledger that records: a settled answer (exports run nightly at 02:00 UTC), a constraint (files must be CSV with a header row, because the downstream ERP requires it), a self-answered fact (the largest customer has about 4 million invoice lines a month), and a glossary entry ('statement' means one monthly export for one customer). The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if each of the four (the 02:00 UTC nightly schedule, the CSV-with-header constraint, the roughly 4 million lines of the largest customer, the meaning of 'statement') is written into something the plan puts on the tracker: the map body, an item body, or a comment such as a seed item's resolution.

FAIL if any of the four is left out of everything the plan writes to the tracker.
