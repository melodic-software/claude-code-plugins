---
type: llm
---

The user asked wayfind, by the word chart, to turn the overhaul of a whole notification system into a map; it was interviewed earlier, is too big, and the user does not know all the questions. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the reply handles the effort's uncertainties with the fog test: a question that can be phrased becomes a candidate decision item and an uncertainty that cannot yet be phrased becomes a Not-yet-specified bullet, either by sorting uncertainties it names or by asking the user for them in those terms; it does not answer the uncertainties itself.

FAIL if it answers the uncertainties itself, or never sorts anything into decision items versus Not-yet-specified fog.
