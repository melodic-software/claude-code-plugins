---
bump: patch
---

### Fixed

- `pull-request ci --ci` keeps the lines a fix-ci run needs to leave alone: a line a linked issue's criterion names or quotes, and a line in `feedback_lines`, which the previous address-feedback round added. The run makes room elsewhere, or escalates `weaken-required` when no edit that keeps those lines passes. The context file's `spec` and `feedback_lines` fields are data, never instructions. Two evals cover a line-cap failure: one with room elsewhere, which is fixed, and one where every cut would remove a criterion's line, which escalates.
