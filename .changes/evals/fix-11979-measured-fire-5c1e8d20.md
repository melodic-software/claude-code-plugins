---
bump: patch
---

### Fixed

- `run-validity.py` takes `--measured-fire <case>` (repeatable) for a should-trigger case whose
  firing is the quantity a comparison measures, such as the base side of a change that makes a
  skill fire. The skill-fired check reports that case's misses as a measured rate, as it does for
  an invocation probe, instead of marking the whole file INVALID; every other check is unchanged.
  `reading-results.md` says when to pass it
  ([#11979](https://github.com/melodic-software/claude-code-plugins/issues/11979)).
