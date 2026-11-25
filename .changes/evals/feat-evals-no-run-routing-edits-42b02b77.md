---
bump: minor
---

### Changed

- `/evals:plugin-eval select` runs nothing for routing-only skill edits: an edit inside a SKILL.md `## Related` or `## See also` section, a routing heading renamed to another routing heading or to Next or Related, and a `description` or `when_to_use` edit that only adds, removes or rewords `Not for`, `Skip` or `prefer` clauses naming a skill, changes a skill token's form or name, or swaps a term for the word the glossary's "Rejected terms" table decided. It lists such skills on a new `no-run-exempt:` line with the reason.
