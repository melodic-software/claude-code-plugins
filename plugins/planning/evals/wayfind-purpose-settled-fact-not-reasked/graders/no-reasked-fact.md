---
type: llm
---

The user ran work mode on map #700 'Map: invoice export' in an interactive session. Its frontier item is 'Choose the delivery channel and file retention' (#703, an interview item). Already settled on the map: exports run nightly at 02:00 UTC; files are CSV with a header row; 'statement' means one monthly export for one customer; the largest customer has about 4 million invoice lines a month. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if no question in the reply asks for, or asks to confirm, when exports run, the file format, what a 'statement' is, or how large the largest customer is.

FAIL if any question asks for or asks to confirm one of those settled facts.
