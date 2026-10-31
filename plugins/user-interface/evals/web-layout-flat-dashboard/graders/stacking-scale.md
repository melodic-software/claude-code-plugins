---
type: llm
arm: both
---
The request asks for revised CSS, not an audit sweep, so the spoke's "define a scale" applies here
and its "don't invent one mid-sweep" does not.
PASS only if the reply's revised CSS (the code it proposes, not a quoted original or a block marked
as before) defines named z-index tokens as custom properties (for example `--z-modal`,
`--z-toast`) and gives the modal and the toast their `z-index` from those tokens, so no proposed
rule keeps `z-index: 9999` or `z-index: 1000`, with or without a trailing semicolon. Quoting the
original values as the thing being replaced does not decide the verdict.
FAIL if any proposed rule keeps 9999 or 1000 as a `z-index` value, if the tokens are used but never
defined, if the only stacking change is `isolation: isolate` while the toast keeps its large value,
or if the reply contains no CSS.
