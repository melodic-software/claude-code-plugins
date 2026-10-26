---
bump: minor
---

### Added

- A skill leaf's optional `tidy`: `entry` (the diff-scoped tidy skill), `passes` (the other quality skills it may call), `turn-share` (the percent of the run's turn cap tidy may spend) and `cutoffs` (`max-files`, `max-lines`, `max-areas`, `shared-paths`), the one value that decides whether a change is small and single-area enough to tidy in the run. The schema takes it only on a `read` skill whose `applied-by` sets `patch` with no `prepare`. `resolve-config` carries it on the selected activity. On the launcher, `collect-base-activity` stages the entry's and each pass's plugin read-only under `.lane/plugins`, allows `Skill(<plugin>:<skill>)` for each and no other skill, allows `code-tidying:tidy-diff`'s `change-shape.sh` and the `ai-slop:audit` script rules `fix-docs` already had, and names the cutoffs, the skills and the tidy turn budget in the preamble. `tidy` anywhere but an issue lane's patch skill with no prepare mode on the launcher fails the stage red.
- `resolve-issue` tidies its own change before its last check run and before its review, with `code-tidying:tidy-diff` as the entry and `docs-hygiene:write-for-agents`, `docs-hygiene:write-for-humans` and `ai-slop:audit` as the passes, 25% of its turns, and cutoffs of 10 files, 300 changed lines, one area and no change under `.github/`, `.claude/`, `.claude-plugin/`, `scripts/`, `lib/`, `docs/conventions/`, `docs/standards/`, `AGENTS.md` or `CLAUDE.md`. The PR then reaches review tidied with no extra push, review run or token mint; pr-refine's skip for lane PRs stays.
