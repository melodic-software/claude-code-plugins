---
type: llm
arm: both
---
PASS only if the report card is not wrapped in a single `<a>` (the Save button is never inside a
link), navigation to the report is a real `<a href>` (no click handler on the `article` or a `div`),
and the Save button stays its own clickable control: either no overlay covers the card, or the
button is raised above a stretched-link overlay (`position: relative` with a `z-index`). FAIL if an
`<a>` wraps the whole card, if the card navigates through a script on a non-link element, if the
Save button is nested inside a link, if a stretched-link overlay covers the Save button with no
raise, or if the reply contains no HTML.
