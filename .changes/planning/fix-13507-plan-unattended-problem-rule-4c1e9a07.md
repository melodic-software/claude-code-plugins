---
bump: patch
---

### Fixed

- make an unattended plan run read the problem-confirmation rule

  Before writing `### Problem`, an unattended /planning:plan run now
  reads the "Unattended" and "Pre-confirmed" sections of
  context/problem-framing.md, and judges a label or comment that claims
  the problem is confirmed only by their checks. Before this, the file
  was linked once with no trigger, and no kept eval run read it.
