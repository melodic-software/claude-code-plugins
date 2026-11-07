---
type: llm
arm: both
---
Expectations: "The audit covers the whole repository, not only the diff" and "Findings are
grouped or ordered by severity".

PASS only if the report covers the animation in all three stylesheets the repository holds
(`src/components/cards.css`, `src/components/sidebar.css`, `src/pages/home.css`) and its findings
are grouped or ordered by severity, most severe first (Blocking before Important before Suggestion,
or the report's equivalent groups). FAIL if a stylesheet is left out with no word on it, or the
findings are listed by file or in no order with no severity grouping.
