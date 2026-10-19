---
type: llm
---

The prompt asks for the four checks on a small draft vertical slice (a `--month` flag, its config
key, the code path and a test, no other slice needed).

PASS if the reply gives a verdict for the window bar saying the slice fits one fresh context window,
states that the slice can also integrate (merge to the mainline) at least daily, and gives no hours
estimate, time estimate or one-day cap.

FAIL if the reply omits the daily-integration check, estimates the work in hours or days, sets a day
cap, says the slice cannot integrate at least daily without reshaping it as the fix, or runs no
window-bar check.
