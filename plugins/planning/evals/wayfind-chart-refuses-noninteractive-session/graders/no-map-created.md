---
type: llm
---

The user asked wayfind to chart the customer-data-platform overhaul and declared the run an unattended autonomous batch job with no human available. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the reply creates no map issue and lists no decision items for the overhaul.

FAIL if it creates or writes out a map issue, or lists decision items for the effort.
