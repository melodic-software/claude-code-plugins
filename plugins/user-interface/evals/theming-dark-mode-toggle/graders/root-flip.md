---
type: llm
arm: both
---
PASS only if the reply's CSS gives the dark theme its colors by flipping one set of color variables
once, at the theme root, under a class or attribute the toggle sets on the root element, and the
header, card and button read those variables: the variables are redefined under a single root-level
dark selector the toggle sets (`[data-theme="dark"]`, `.dark` or `html.dark`), or each token holds
both values with `light-dark()` and the toggle switches it by setting `color-scheme` through such a
selector. A `prefers-color-scheme` default beside that selector also passes. Either mechanism
passes: the rule graded is the flip once at the root, not which of the two it uses. FAIL if the
dark values apply only inside `@media (prefers-color-scheme: dark)` or only through `color-scheme:
light dark` on `:root`, with no selector the toggle can set (a toggle cannot drive the OS setting),
if any component gets its own dark color rule (`.dark .card { background: ... }`, `dark:` utility
classes on each component), if the variables are redefined per component under the dark selector
(`.dark .card { --bg: ... }`), if a component keeps a hardcoded color that does not flip, if the
flip appears only in prose, or if the reply contains no CSS.
