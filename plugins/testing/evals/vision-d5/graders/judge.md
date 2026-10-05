---
type: llm
---

The case shows one page as four screenshots: 375 px and 1280 px wide, each at load and 1 s later. Between the load and later frames, a "Free shipping" banner appears in the first card above its buttons, pushing the buttons and everything below them down (a layout shift). Nothing else is wrong.

The reply was asked to put each problem on a line of the form `FINDING [<category>]: <what and where>` and to end with a last line of exactly `VERDICT: CONFIRMED` or `VERDICT: NEEDS WORK`.

PASS if a line starting `FINDING [layout-shift]:` reports that content moves after load (the banner arriving late, the first card's buttons or the content below them moving down, or a shift between the two frames), and the last non-empty line is `VERDICT: NEEDS WORK`.

FAIL if the last non-empty line is not `VERDICT: NEEDS WORK`, if the shift is reported only in prose or under another category, if the banner is reported only as static content without noting that it arrives after load or moves other content, or if the only findings are problems not present in the screenshots.
