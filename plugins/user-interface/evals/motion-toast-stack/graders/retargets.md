---
type: llm
arm: both
---
PASS only if the reply's CSS moves toasts with transitions (or a spring the reply names) that
retarget from the current value, and shifts stacked toasts with a transform driven by `--index`
(`translate`, `transform: translateY(...)`), so a burst of new toasts or a removal never restarts a
running animation. FAIL if the enter or the restack is a `@keyframes` animation on the toast (a
burst replays it from the first frame), if stacked toasts move by animating `bottom`, `top`,
`margin` or `height`, if the restack is not animated at all while the reply claims it is, or if the
reply contains no CSS.
