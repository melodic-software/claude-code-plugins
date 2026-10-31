---
type: llm
arm: both
---
PASS only if the reply's CSS animates the dialog's `::backdrop` (or an overlay element the reply
adds) with exactly the same duration and the same easing as the dialog's own opacity, on the way
in and on the way out. FAIL if the backdrop has no transition or animation, if its duration differs
from the dialog's (for example 150ms against 250ms), if its easing differs from the dialog's, if
the pairing appears only in prose, or if the reply contains no CSS.
