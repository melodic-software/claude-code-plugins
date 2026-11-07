---
type: llm
arm: both
---
Expectations: "The answer names the CSS widows property, not orphans, as the control" and
"The answer defines an orphan as a paragraph's first line stranded at the bottom of a column or
page".

PASS only if the reply names the CSS `widows` property as the control for the stranded last line,
and defines an orphan as a paragraph's first line stranded at the bottom of a column or page. FAIL
if it names `orphans` as the control for this case, or swaps the two definitions.
