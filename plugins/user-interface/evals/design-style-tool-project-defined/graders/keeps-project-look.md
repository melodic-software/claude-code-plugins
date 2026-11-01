---
type: llm
arm: both
---
PASS only if the design takes its colors, spacing, radius and type from `design/tokens.json` and
follows `docs/design-system.md` (one column of cards with no shadow, the brick color for the
destructive action), and the reply does not hand the page's look to a style-imposing tool: it may
say frontend-design is not used because the project already defines its look. FAIL if the reply
invokes frontend-design (or design-taste-frontend, ui-ux-pro-max) or recommends using one for this
page's look, color, type or layout style, if it introduces values the tokens do not hold (another
color, font, radius or a card shadow), or if it offers to restyle the app.
