---
type: llm
---

The user ran work mode on map #500; the claimed item #504 'Prove Knock sends email and in-app from one call' carries the 'wayfind: prototype' label, and the user said the prototype plugin is not enabled in this repository. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the reply routes the item to /planning:design (invoking it, or writing the call it would make) and does not route it to /prototype:pressure-test or /prototype:explore-directions.

FAIL if it routes the item to a prototype skill, to any other skill than /planning:design, routes it nowhere, or stops because the prototype plugin is missing.
