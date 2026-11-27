---
bump: minor
---

### Added

- `observer_skill_check` and `observer_improvement_check` (off by default) add `skill` and `improvement` categories to the live checks: work done by hand where a skill or written rule assigns it to a skill, or a skill run that missed a case, ran inefficiently or skipped its `## Next`; and a step that ran far too long, a failure not raised, or work against a principle the repository's docs state.
- A repository's `docs/conventions/session-flow.yaml` takes an `observer` map (`skill_check`, `improvement_check`, `defer_kinds`, `codify_threshold`) that wins over the matching user options, and its `session-flow.md` an `## Observer guidance` section added to every check; both are read from the default branch only.
- `observer_defer_kinds` (empty by default) holds the listed categories found mid-turn until the turn ends, then sends them in one observer turn.
- A live finding may end with `fix: session` (a dedicated session with a ready command, never auto-sent) or `fix: issue`; a missing line means here.
- With `observer_harness_check` on, a rule cited by `observer_codify_threshold` (default 3) shown findings across two or more sessions raises one finding suggesting a dedicated `/corrections:codify` session. `shown` usage rows now carry the redacted `rule`.
