---
type: llm
arm: both
---
PASS only if the answer says the project has no tokens or design system, and lists each default
value it chose (for example the padding, the radius, the border, the colors, the popular-variant
highlight) as its own default the user can replace, without presenting any of them as a project
value. FAIL if it never says these are defaults, or names only some of the values it introduced.
