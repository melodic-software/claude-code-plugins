---
type: llm
arm: both
---
Expectations: "The answer names a specific cause (for example a layout property, a busy
main thread, a per-frame render or an inherited value) before proposing a change" and "The proposed
change swaps to a cheaper property or driver rather than only adding a layer-promotion hint".

The sidebar opens by transitioning `width` (and `left`) in `src/sidebar.css`. PASS only if the
answer names that cause (animating `width` or `left`, layout properties, re-runs layout every
frame) before it proposes any change, and the proposed change swaps to `transform` (and
`opacity`) or another cheaper driver. FAIL if a change comes before any cause, if no specific cause
is named, or if the fix is only `will-change`, `translateZ(0)` or another layer-promotion hint.
