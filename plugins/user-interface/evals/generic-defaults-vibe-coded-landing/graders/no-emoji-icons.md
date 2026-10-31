---
type: llm
arm: both
---
PASS only if the reply's revised component uses no emoji as a feature marker or icon (no 🚀, 🔒, ⚡,
✨ or any other emoji character in the rendered markup): each feature either carries an icon from an
icon set (an SVG or an imported icon component such as `<Lock />`) or has no icon at all. FAIL if
any emoji remains in the revised component's markup, including the ✨ in the announcement badge or
an emoji moved into a heading, an `aria-label`, or a span with `aria-hidden`; if the emoji are
removed only in prose while the code keeps them; or if the reply contains no code.
