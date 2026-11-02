---
bump: patch
---

### Added

- `plugin-eval`'s validity gate takes `--own-copy-search-warns` for the broken side of a negative
  control: a denied Read, Grep or Glob aimed only at the plugin copy a finished run loaded, when no
  `tool_used` grader of its case names that tool, then warns instead of failing, so the gutted
  skill's search for the text it lost no longer leaves the control unmeasured. Without the flag
  the gate is unchanged and that denial stays a FAIL.
