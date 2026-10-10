---
type: llm
---

The case shows one page as four screenshots: 375 px and 1280 px wide, each at load and 1 s later. Between the load and later frames, a "Free shipping" banner appears in the first card above its buttons, pushing the buttons and everything below them down (a layout shift). Nothing else is wrong.

The reply was asked to put each problem on a line of the form `FINDING [<category>]: <what and where>` and to end with a last line of exactly `VERDICT: CONFIRMED` or `VERDICT: NEEDS WORK`.

PASS only if a line starting `FINDING [layout-shift]:` (a markdown prefix or emphasis is allowed, such as a `-` or `1.` list marker, or `**FINDING [layout-shift]:**`) asserts that content moves after load (the banner arriving late, the first card's buttons or the content below them moving down, or a shift between the two frames), says where (the first card, its buttons, or the banner), and the last non-empty line is `VERDICT: NEEDS WORK`. A negation that asserts the defect, such as "the buttons are not where they were at load", is an assertion.

FAIL if any of these holds:

- the `FINDING [layout-shift]:` line denies the shift, says it was not seen, or reports the frames as checked and identical;
- it hedges ("may shift", "possibly", "hard to tell") instead of asserting the shift;
- it gives no location;
- the banner is reported only as static content without noting that it arrives after load or moves other content;
- the shift is reported only in prose or under another category, or the only findings name other problems;
- the last non-empty line is not `VERDICT: NEEDS WORK`.

These lines carry the right tag but deny the defect, so each one FAILs:

- `FINDING [layout-shift]: I cannot see any movement between the load and 1 s frames.`
- `FINDING [layout-shift]: The buttons don’t move after load.`
- `FINDING [layout-shift]: Layout shift appears nowhere on the page.`
- `FINDING [layout-shift]: The first card is NOT shifted.`
- `FINDING [layout-shift]: Compared both frames: they are identical.`
- `FINDING [layout-shift]: Content stays in place after load.`
- `FINDING [layout-shift]: Unable to detect any shift.`
- `FINDING [layout-shift]: Layout-shift check passed.`
- `FINDING [layout-shift]: N.A.`
