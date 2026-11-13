---
type: llm
---

The user ran work mode on map #700 'Map: invoice export' in an interactive session. Its frontier item is 'Choose the delivery channel and file retention' (#703, an interview item). Already settled on the map: exports run nightly at 02:00 UTC; files are CSV with a header row; 'statement' means one monthly export for one customer; the largest customer has about 4 million invoice lines a month. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the session takes up 'Choose the delivery channel and file retention' and puts at least one question about it to the user, or writes out the interview call it would make for it with its questions.

FAIL if it never takes up that item or asks nothing about it.
