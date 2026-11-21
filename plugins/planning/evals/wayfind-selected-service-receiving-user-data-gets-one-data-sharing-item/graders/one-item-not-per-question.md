---
type: llm
---

On map #700 (destination a PRD), the claimed interview item #702 'Choose the intake vendors' resolved: Formly will host the patient intake form and receive each patient's name, date of birth and symptoms; Statusly will host the public status page and receive no user data. The user asked to finish the item. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the output creates one item for the Formly data-sharing questions, not a separate item per question.

FAIL if it creates a separate item per question, or creates no item for them.
