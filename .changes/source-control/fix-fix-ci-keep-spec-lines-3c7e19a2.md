---
bump: patch
---

### Fixed

- `pull-request ci --ci` no longer cuts a line the linked issue's spec needs to pass a check. The
  context file now carries the issue's trusted spec text (`spec`) and the lines the last
  address-feedback commit added (`feedback_lines`). The skill makes room elsewhere for them, or
  escalates `weaken-required` when the only cut that passes would remove or rewrite one, so fix-ci
  and address-feedback no longer undo each other.
