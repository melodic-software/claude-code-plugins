---
type: llm
arm: both
---
PASS only if the reply's revised CSS (the code it proposes, not a quoted original or a block marked
as before) spaces the `.stat` items with `gap` (or `row-gap`, `column-gap`, or a Tailwind `gap-*`
utility) on their parent `.stats`, and no proposed `.stat` rule keeps a `margin-bottom` (or a
block-end margin) for that spacing.
FAIL if `.stat` keeps a `margin-bottom` in the proposed CSS, even when `gap` is added somewhere,
if `gap` appears only on an element other than the stats' parent, if `gap` is named only in prose,
or if the reply contains no CSS.
