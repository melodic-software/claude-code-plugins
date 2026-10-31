---
type: llm
arm: both
---
PASS only if the reply removes the browser's tap highlight (`-webkit-tap-highlight-color:
transparent` or a fully transparent color) and gives every tappable element in the toolbar, the
three buttons and the Profile link, its own pressed state through `:active` (or a class set on
`pointerdown`). FAIL if the highlight is removed while any of the four controls, the link included,
has no pressed state; if the pressed look is set from a `click` listener; if the highlight is left
on; or if the reply contains no CSS.
