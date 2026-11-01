---
type: llm
arm: both
---
PASS only if the reply's proposed CSS (or utility classes) makes the email input's computed font
size at least 16px on touch devices: an absolute `16px` or larger, `max(16px, 1rem)`, `1rem` only
when the reply also sets the root font size back to 16px or more, or a smaller desktop size gated
on the pointer (inside `(pointer: fine)`, outside `(pointer: coarse)`, or a utility such as
`pointer-fine:text-sm`) with 16px or more everywhere else. Read the root font size from the prompt:
the page sets `html { font-size: 87.5%; }`, so `1rem` there computes to 14px. FAIL if the input
stays under 16px on touch, if it is set to `1rem` while the root stays at 87.5% (a near miss: it
computes to 14px), if the smaller size is gated on screen width alone (`md:text-sm`,
`@media (min-width: …)`; a near miss: a touch tablet wider than the breakpoint gets the small size
and zooms), if the size is raised only on desktop or only on focus, if the reply fixes the zoom
only through the viewport tag, if the fix appears only in prose, or if the reply contains no CSS.
