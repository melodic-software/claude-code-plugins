---
bump: patch
---

### Changed

- `/playwright:demo-video`: the click ripple now clamps its gap per frame side, so a target near one edge keeps the full ring on the other three sides, and an unzoomed click on a small target (longer side under 120 output px) draws a ring with a doubled gap and stroke so it reads. Zoomed clicks and the edge-clip rule are unchanged.
