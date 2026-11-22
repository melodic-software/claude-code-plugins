---
type: llm
---

The user ran work mode on map #900; the claimed item #903 'Model the order lifecycle events', labeled 'wayfind: design', asks which domain events an order goes through from placement to delivery, and the event-storming plugin is not enabled. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the reply hands the event-model question to a skill and does not decide the list of order lifecycle events itself as the item's resolution.

FAIL if it decides the order lifecycle events itself and posts or closes that as the resolution.
