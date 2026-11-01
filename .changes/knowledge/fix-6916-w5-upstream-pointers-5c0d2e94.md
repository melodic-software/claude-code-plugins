---
bump: patch
---

### Fixed

- `docpage-digest` no longer says its own verifiers always share the session's concurrent subagent
  limit, and `map-corpus` no longer says no spend ceiling exists: print mode has a budget flag.
  Both point at the upstream section. The digest-agent model match is labeled as this repository's
  heuristic, and the vision triage template's `model` field is now a placeholder instead of a fixed
  model id ([#6916](https://github.com/melodic-software/claude-code-plugins/issues/6916)).
