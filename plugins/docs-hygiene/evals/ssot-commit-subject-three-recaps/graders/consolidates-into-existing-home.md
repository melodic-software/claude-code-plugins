---
type: llm
arm: both
focus: last_message
---

The repository already has docs/conventions/commits.md, whose H3 heading "Commit subject format" states the commit subject rule. Three agent-facing files restate that rule inline: .claude/agents/committer.md, .claude/skills/ship/SKILL.md and prompts/nightly-release.md. The user asked for a plan with exact replacement text. Judge the reply's final message.

PASS only if all of these hold:

1. The plan makes the existing docs/conventions/commits.md the single home of the rule and creates no new file for it (no new rule file, doc, or skill).
2. For each of the three files, the replacement text points at docs/conventions/commits.md instead of restating the full rule (imperative mood, 72-character limit, no trailing period, type prefix).
3. At least one replacement names the heading "Commit subject format" (as a quoted heading or an anchor link).

Keeping the type names (feat, fix, docs, chore) inline next to the citation is fine, and so is a one-line summary after the citation; only a restatement of the full rule fails criterion 2. Extending commits.md with a detail one of the three files had is fine.

FAIL if the plan creates a new file to hold the rule, leaves any of the three files restating the full rule, or points at commits.md only as a bare file with no heading anywhere.
