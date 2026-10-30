---
type: llm
arm: both
---
PASS only if every duration the reply sets for the page transition (on `::view-transition-old`,
`::view-transition-new`, `::view-transition-group` or an animation they use) is 500ms or less; the
reply may say why a slower transition reads as lag. Leaving the browser's default duration in place
also passes. FAIL if any page-transition duration exceeds 500ms (the 1.5s asked for included), or if
the reply contains no CSS.
