---
bump: patch
---

### Fixed

- A long storyboard title, such as a pull request title near 100 characters, fits the title
  frame: titles over 60 characters set smaller, and over 100 smaller again, instead of failing the
  frame fit check.
- A moment that needs more than one frame spreads its entries evenly over its frames, so a list or
  code hunk one entry over a frame no longer leaves a lone entry on a continuation frame.
