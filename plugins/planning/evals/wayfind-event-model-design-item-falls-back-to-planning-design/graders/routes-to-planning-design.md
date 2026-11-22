---
type: llm
---

The user ran work mode on map #900; the claimed item #903 'Model the order lifecycle events', labeled 'wayfind: design', asks which domain events an order goes through. That is domain/event-model work, and the user said the event-storming plugin is not enabled in this repository. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the reply routes the item to /planning:design (invoking it, or writing the call it would make) and does not route it to /event-storming:methodology or /event-storming:simulation.

FAIL if it routes the item to an event-storming skill, to any other skill than /planning:design, routes it nowhere, or stops because the event-storming plugin is missing.
