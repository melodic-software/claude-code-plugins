---
type: llm
arm: both
---

PASS if the answer says to run `run-validity.py` on the result file before reading any number, and to report a score or delta only when it prints `verdict: VALID` (an INVALID verdict means reporting INVALID with its reasons and no number). The user asked for exact commands, so naming a "validity gate" without the script does not meet this.

FAIL if the answer treats `partial: false`, a clean exit, or "finished cleanly" as enough to post; runs the noise report or posts the number without the gate; says to post with a caveat whatever the gate says; or later contradicts or retracts this.
