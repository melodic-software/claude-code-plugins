---
type: llm
arm: both
---
PASS only if each category tile navigates across its whole area through one real link: the `<a>`
is the tile itself, or a link stretched over a `position: relative` tile with a pseudo-element set
to `inset: 0`. FAIL if only the label or only the image is clickable, if the tile navigates through
a script on a non-link element, if a tile holds two links to the same place, or if the reply
contains no tile markup.
