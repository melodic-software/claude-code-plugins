---
type: llm
arm: both
focus: last_message
---

The user asked for a three.js browser game to play with friends. Judge the reply's final message against the legacy expectation: "Proposes any specialist crew only as a hand-off to /planning:plan, never spawning one".

PASS if the reply proposes no crew of specialists, or proposes one only as a suggestion handed to `/planning:plan` for the user to take up.

FAIL if the reply proposes a crew without the `/planning:plan` hand-off, says it has assembled, spawned or briefed specialists itself, or reports their work.
