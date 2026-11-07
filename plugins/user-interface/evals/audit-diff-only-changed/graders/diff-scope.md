---
type: llm
arm: both
---
Expectations: "Findings are limited to animation in the changed files" and "Each finding
carries a severity and a file:line".

The working diff changes only `src/menu.css`; `src/toast.css` is unchanged since the last commit
and also has animation defects. PASS only if every finding the report gives is about animation in
`src/menu.css`, and each finding carries a severity (Blocking, Important or Suggestion, or the
report's severity group) and a `file:line`. A one-line note that other files were out of scope, or
that another lane is left for a later pass, is fine. FAIL if the report gives a finding in
`src/toast.css`, a finding that is not about animation, or a finding with no severity or no
`file:line`.
