---
type: llm
---

The case shows one page as four screenshots: 375 px and 1280 px wide, each at load and 1 s later. Between the load and later frames, a "Free shipping" banner appears in the first card above its buttons, pushing the buttons and everything below them down (a layout shift). Nothing else is wrong.

PASS if the reply reports that content moves after load: the banner arriving late, the first card's buttons or the content below them moving down, or a layout shift between the two frames, and ends with VERDICT: NEEDS WORK.

FAIL if the reply ends with VERDICT: CONFIRMED, if it reports the banner only as static content without noting that it arrives after load or moves other content, or if its only findings are problems not present in the screenshots.
