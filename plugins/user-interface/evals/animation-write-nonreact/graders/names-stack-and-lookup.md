---
type: llm
focus: trace
arm: both
---
Expectations: "The stack is named from the project files before any code is written" and
"The answer looks up or cites the stack's own current animation documentation, or says no lookup
route was available and follows the repo's existing patterns".

PASS only if, before its code, the run names the stack as Svelte from the project files (the
`.svelte` component, package.json) and looks up or cites Svelte's own current animation
documentation, or says no lookup route was available and follows the repository's existing
patterns. FAIL if the code comes with no stack named from files, or the run relies on recalled
syntax with no lookup and no word on the missing route.
