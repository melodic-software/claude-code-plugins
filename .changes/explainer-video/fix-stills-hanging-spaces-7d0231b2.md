---
bump: patch
---

### Fixed

- A code line that wraps at a space no longer fails the frame fit check: the space at the wrap
  point used to hang past the content area's right edge.
- A flow diagram keeps its nodes and arrows on one row, wrapping text inside each node with
  balanced lines, instead of wrapping a node onto a second row after a dangling arrow.
