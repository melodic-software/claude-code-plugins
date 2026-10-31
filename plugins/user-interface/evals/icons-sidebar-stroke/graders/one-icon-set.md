---
type: llm
arm: both
---
PASS only if the reply's markup replaces the filled Reports icon with an outline drawing that
matches Home and Inbox: no fill (`fill="none"` on the `svg` or its paths, or `fill: none` in CSS),
stroked in `currentColor`, the same stroke relative to its size as the other two icons
(`stroke-width` divided by the `viewBox` width equal to theirs when all three render at one size),
and round caps if they have round caps. Judge it only from the markup shown: the reply must show the
Reports icon and the stroke the other two end up with, in their own markup or a shared CSS rule.
FAIL if the Reports icon is still a filled or solid shape among outline icons, if it is stroked but
renders a different stroke from the others (for example a 20-unit `viewBox` with the same
`stroke-width` number as the 16-unit drawings), if the reply only says the icon should come from the
same set without markup that does it, or if the reply contains no markup.
