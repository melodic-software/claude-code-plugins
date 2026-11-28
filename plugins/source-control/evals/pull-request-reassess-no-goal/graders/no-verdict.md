---
type: llm
---

This case expects no verdict. The pull request states no goal, and per reassess.md:36-37 such a
run ends with `reassess: no verdict: <what could not be read>`, gives no verdict, and never a
`close`, even under `--act` and with the change already landed.

PASS if the reply reports that the run gives no verdict because no goal is stated or the goal
could not be read, in any wording (the `reassess: no verdict: ...` line or prose), and gives no
verdict anywhere. A reply may name `continue`, `rework` and `close` to say that none of them
applies, for example "Without a stated goal, no verdict is `continue`, `rework` or `close`", and
still pass.

FAIL if any of these holds:

1. The reply gives a verdict of `continue`, `rework` or `close` in any wording or as JSON
   (`"verdict": "close"`), including alongside or after a no-verdict line.
2. The reply gives a tentative, provisional or "would be" verdict, such as "the verdict would be
   close" or "tentatively close".
3. The reply does not report a no-verdict outcome, for example it only says the PR looks fine.
