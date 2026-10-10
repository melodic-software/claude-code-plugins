---
type: llm
---

The case shows one page as four screenshots: 375 px and 1280 px wide, each at load and 1 s later. At 375 px each card's badge sits on top of its product title, covering part of it (an overlap). The 1280 px screenshots are clean. Nothing else is wrong.

The reply was asked to put each problem on a line of the form `FINDING [<category>]: <what and where>` and to end with a last line of exactly `VERDICT: CONFIRMED` or `VERDICT: NEEDS WORK`.

PASS only if a line starting `FINDING [overlap]:` asserts that the badge covers or collides with the product title, says where (the cards, the badge and title, or the 375 px width), and the last non-empty line is `VERDICT: NEEDS WORK`. A negation that asserts the defect, such as "the title is not readable because the badge covers it", is an assertion.

FAIL if any of these holds:

- the `FINDING [overlap]:` line denies the overlap, says it was not seen, or reports it as checked and fine;
- it hedges ("may overlap", "possibly", "hard to tell") instead of asserting the overlap;
- it gives no location, or places the overlap only at 1280 px;
- the overlap is reported only in prose or under another category, or the only findings name other problems;
- the last non-empty line is not `VERDICT: NEEDS WORK`.

These lines carry the right tag but deny the defect, so each one FAILs:

- `FINDING [overlap]: I cannot see any overlap between the badge and the title.`
- `FINDING [overlap]: The badge isn’t overlapping the title at either width.`
- `FINDING [overlap]: Overlap doesn’t appear in either screenshot.`
- `FINDING [overlap]: The title is NOT covered by the badge.`
- `FINDING [overlap]: Looked for overlap: none found.`
- `FINDING [overlap]: Did not observe overlapping elements.`
- `FINDING [overlap]: Canʼt see overlap.`
- `FINDING [overlap]: Overlap check passed.`
- `FINDING [overlap]: The title is fully visible at 375 px.`
- `FINDING [overlap]: N.A.`
