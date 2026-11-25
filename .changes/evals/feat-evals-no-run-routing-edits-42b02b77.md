---
bump: minor
---

### Changed

- `/evals:plugin-eval select` runs nothing for routing-only skill edits: an edit inside a SKILL.md `## Related` or `## See also` section, a routing heading renamed to another routing heading or to Next or Related, and a `description` or `when_to_use` edit that only adds, removes or rewords `Not for`, `Skip` or `prefer` clauses naming a skill, or changes a skill token's form or name. It lists such skills on a new `no-run-exempt:` line with the reason.
- `select` also runs nothing for a decided-term swap wherever it looks: a skill body, reference or agent hunk, a frontmatter value, an eval case file, or a renamed file whose only difference swaps a term for the word the glossary's "Rejected terms" table decided (or that word's last word, as `--lane` to `--area`). A hunk with any other change keeps today's rule.
