# SKILL.md hubs past the re-attach slice

Park for [#4255](https://github.com/melodic-software/claude-code-plugins/issues/4255).

## Decision

**Do not split or reorder the five hubs in this session.** The issue is
`needs-human` and `work-class: structural`. It names `planning` `plan`,
`discovery` `explore` and `research`, `implementation` `implement-dispatch`,
and `source-control` `worktree`. Moving gates into the first 5,000 tokens is a
multi-plugin contract change, not a one-file trim.

**Claim:** After compaction, Claude Code re-attaches only the first 5,000
tokens of each invoked skill, in a shared 25,000-token budget. Hubs whose
mandatory gates sit past that slice can drop those gates. Doing the move is
unpaid structural work.
**Basis:** [Skills](https://code.claude.com/docs/en/skills), fetched 2026-09-28:
"When the conversation is summarized to free context, Claude Code re-attaches
the most recent invocation of each skill after the summary, keeping the first
5,000 tokens of each. Re-attached skills share a combined budget of 25,000
tokens." The issue's own byte counts (2026-09-19) put `plan/SKILL.md` at
42,249 bytes, with the outcome gate past a 20,000-byte cut.
**As of:** 2026-09-28.
**Recheck:** An operator funds one hub at a time, starting with `plan`, and
the move keeps every gate the skill calls mandatory inside the first 5,000
tokens. A skills-page change to the 5,000-token figure also reopens this.

## What this close is not

Not a measurement that the current files still exceed the slice. Re-measure
before editing.
