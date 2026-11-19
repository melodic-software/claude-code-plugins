---
bump: patch
---

### Fixed

- lift a read-back record on a C2 or C3 merge pin

  The merge policy's read-back check matched only a pin comment with no
  rung, so a pull request merged at rung C2 or C3, whose pin carries
  `rung=C2` or `rung=C3`, never read back, and its read-back record could
  never lift. The pin pattern now accepts the optional rung, as the
  post-merge reader already does.
