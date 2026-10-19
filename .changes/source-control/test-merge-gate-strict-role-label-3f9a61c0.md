---
bump: patch
---

### Fixed

- `pr-merge.yml` passes the human-gated label to the prefilter as `--human-gated=<label>`, so a label starting with `-` cannot be read as another option. A test now runs the merge gate through the real `_role_label` read over a 502 and proves it refuses and caches nothing, and `reference/safety.md` names the human-gated label instead of the literal `needs-human`.
