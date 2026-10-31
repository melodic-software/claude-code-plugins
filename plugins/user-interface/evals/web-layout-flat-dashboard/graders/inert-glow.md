---
type: llm
arm: both
---
PASS only if the reply's revised code (the code it proposes, not a quoted original or a block marked
as before) keeps the glow and puts `pointer-events: none`, or the Tailwind `pointer-events-none`
class, on the glow element itself (`.hero-glow` or the element that replaces it), so clicks pass
through to the buttons beneath it.
FAIL if `pointer-events: none` lands only on `.actions`, the buttons or another element, since that
kills the buttons instead; if the glow is deleted or moved behind the actions, which the request
rules out; if the glow gets `pointer-events` with any value other than `none`; if only the prose
says to make the glow inert while the proposed code does not; or if the reply contains no code.
