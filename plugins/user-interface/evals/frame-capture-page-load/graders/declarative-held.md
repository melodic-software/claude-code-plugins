---
type: llm
arm: both
---
The hero entrance is CSS keyframes (declarative motion); the counter runs on
`requestAnimationFrame` (script-driven). PASS only if the reply reads the CSS entrance frame by
frame in a way that holds it still: it pauses and seeks the declarative animations (for example
`document.getAnimations()` with `pause()` and `currentTime`), and it reads values per frame from
the page's computed style, not from pixels. FAIL if it expects stepping the page clock alone to
step the CSS keyframes, samples the CSS entrance only by waiting real time between screenshots,
reads values from `element.style` for the CSS entrance, or treats a video as the frame-by-frame
record.
