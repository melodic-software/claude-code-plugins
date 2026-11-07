---
type: llm
arm: both
focus: last_message
---

The user asked for a three.js browser game to play with friends. Judge the reply's final message against the legacy expectation: "When the raised request leaves several open decisions, names /planning:interview as the next step".

First decide whether the raised request leaves several (two or more) open decisions for the user, such as the genre, the number of players, hosting or how friends join.

PASS if it leaves several open decisions and the reply names `/planning:interview` as the next step, or if it leaves at most one open decision.

FAIL if it leaves several open decisions and `/planning:interview` is not named.
