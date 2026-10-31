---
type: llm
arm: both
---
PASS only if the reply's CSS caps the width of the article body column at roughly 45 to 75
characters: `max-width` or `max-inline-size` of about `65ch` (any value from `45ch` to `75ch`), or a
rem or em width the reply says holds about that many characters, or a project token the reply says
sets that measure.
FAIL if the reply sets no width cap on the body text, caps it at a value it does not tie to a
character count (`max-width: 1200px` for the whole page), or caps it above 75 characters.
