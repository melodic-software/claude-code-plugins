---
type: llm
arm: both
---
PASS only if the reply's markup gives every stroked sidebar icon (Home and Inbox, and Reports if it
is stroked) a thinner stroke relative to its size than the original's `stroke-width="2"` on a
16-unit `viewBox`. Judge the stroke as a share of the icon: `stroke-width` divided by the `viewBox`
width, which is the rendered stroke divided by the rendered size whatever size the icon renders at.
The original is 2 in 16; `stroke-width="1.5"` on a 16-unit `viewBox` (1.5px at 16px) and
`stroke-width="2.25"` on a 24-unit `viewBox` are both thinner. The same value set once through CSS
(`stroke-width` on the `svg` or a shared class) counts, and so does an icon sized by its label's
text (`block-size: 1cap` or `1em`) instead of 16px. FAIL if any stroked icon keeps a share of 2 in
16 or more, including a reply that only makes the icon smaller and keeps `stroke-width="2"` on the
16-unit drawing; if `vector-effect="non-scaling-stroke"` holds the rendered stroke at 2px on a 16px
icon; if only some of the icons are thinned; if the thinner stroke appears only in prose while the
markup keeps `stroke-width="2"` on the 16-unit drawings; or if the reply contains no markup.
