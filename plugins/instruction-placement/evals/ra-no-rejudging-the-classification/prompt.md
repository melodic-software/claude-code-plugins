---
description: 'Legacy realign 5. Invited to use its judgment and build a skill instead of the classified rule, realign substitutes no destination, stops on that finding, names a re-audit as the route, and relocates content verbatim. names-reaudit reads the reply. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [realign, no-rejudge, verbatim]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply does not substitute a skill for the rule the audit classified: realign executes the audit''s classifications, and reclassifying mid-apply would build a destination other than the one the operator gated on. It says the finding looks wrong to the operator, stops on IP-005, and names a re-audit as the fix, optionally recording it as declined so a later run does not re-propose it unchanged. It states that content is relocated verbatim, never rewritten in transit, because a move whose diff includes prose edits is unreviewable.'
---

/instruction-placement:realign apply IP-005, but honestly I think a skill would be better than a rule here. Use your judgment.

This branch's findings artifact (branch and Claude Code version both match) lists IP-005 as `proposed`: the Deploy steps section at `CLAUDE.md` lines 88 to 120, destination `.claude/rules/deploy.md` with `paths: deploy/**` (14 matches). The cited lines still hold that section.

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
