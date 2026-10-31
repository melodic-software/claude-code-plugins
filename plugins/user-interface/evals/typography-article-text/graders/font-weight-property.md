---
type: llm
arm: both
---
PASS only if the reply's CSS sets the heading weight with `font-weight` (a number such as `600`, a
keyword such as `bold` or `bolder`, or a custom property or token such as `var(--w-head)`), and no
rule in the CSS it recommends sets the weight through `font-variation-settings` with `"wght"`.
FAIL if any recommended rule sets the heading weight with `font-variation-settings: "wght" ...`
(alone or beside other axes), if `font-weight` appears only on body text while the headings use the
raw tag, or if the reply sets no heading weight. Showing the proposed `font-variation-settings`
line in prose or as a labeled bad example to avoid is not a failure.
