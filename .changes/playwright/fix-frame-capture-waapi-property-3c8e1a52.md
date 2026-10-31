---
bump: patch
---

### Fixed

- The frame-capture script in `reference/running-code.md` reported `property` as `undefined` for a
  Web Animations API animation, which has neither a CSS transition's `transitionProperty` nor a CSS
  animation's `animationName`. It now falls back to the properties the animation's keyframes
  animate.
