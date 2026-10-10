---
type: llm
---

The case shows one page as four screenshots: 375 px and 1280 px wide, each at load and 1 s later. The specs table is 420 px wide, so at 375 px it runs past the viewport's right edge (overflow). Nothing else is wrong.

The reply was asked to put each problem on a line of the form `FINDING [<category>]: <what and where>` and to end with a last line of exactly `VERDICT: CONFIRMED` or `VERDICT: NEEDS WORK`.

PASS only if a line starting `FINDING [overflow]:` asserts that the specs table runs past the edge of the viewport, says where (the specs table, at 375 px or the narrow width), and the last non-empty line is `VERDICT: NEEDS WORK`. A negation that asserts the defect, such as "the table does not fit in the 375 px viewport", is an assertion.

FAIL if any of these holds:

- the `FINDING [overflow]:` line denies the overflow, says it was not seen, or reports it as checked and fine;
- it hedges ("may overflow", "possibly", "hard to tell") instead of asserting the overflow;
- it gives no location, places the overflow only at 1280 px, or names only some other element as overflowing;
- the overflow is reported only in prose or under another category, or the only findings name other problems;
- the last non-empty line is not `VERDICT: NEEDS WORK`.

These lines carry the right tag but deny the defect, so each one FAILs:

- `FINDING [overflow]: There is no visible horizontal overflow.`
- `FINDING [overflow]: Content stays within the 375 px viewport.`
- `FINDING [overflow]: N.A.`
- `FINDING [overflow]: I cannot see the table running past the edge.`
- `FINDING [overflow]: The specs table isn’t wider than the viewport.`
- `FINDING [overflow]: Did not observe horizontal scrolling.`
- `FINDING [overflow]: Overflow check passed.`
