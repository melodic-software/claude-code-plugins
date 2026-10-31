---
type: llm
arm: both
---
PASS only if the reply's CSS staggers the steps' entrance with a gap between consecutive steps of at
least 30ms and at most 80ms, for example `animation-delay: calc(var(--i) * 40ms)` or a delay step of
`0.05s`. FAIL if the gap is over 80ms (the 150ms the prompt asks for included), if it is under 30ms,
if every step enters at once with no per-step delay, if the stagger appears only in prose, or if the
reply contains no CSS.
