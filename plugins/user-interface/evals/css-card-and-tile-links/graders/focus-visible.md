---
type: llm
arm: both
---
PASS only if every link that navigates shows a visible keyboard focus indicator: its own focus ring,
or, where a link is stretched over a card or tile with a pseudo-element, a ring drawn on the
container through `:has(:focus-visible)` or `:focus-within` while the link's own outline is made
transparent rather than removed. FAIL if any navigating link gets `outline: none` or `outline: 0`
with no replacement ring, if no focus style is written for the links, or if focus styles appear only
in prose.
