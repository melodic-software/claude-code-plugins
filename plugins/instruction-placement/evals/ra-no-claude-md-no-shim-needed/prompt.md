---
description: 'Legacy realign 8. Applying a subtree finding in a repository with no CLAUDE.md anywhere, realign creates the nested AGENTS.md without claiming a shim is needed to load it, names render-index.sh wiring''s NATIVE row as the check, justifies any shim only as availability cover, and keeps the rest of the move. names-native-row reads the reply. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [realign, nested-agents-md, native]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply creates src/billing/AGENTS.md with the relocated content and does not claim a shim is what makes it load here: with none of the three CLAUDE.md names on that file''s path, nothing displaces it, so Claude Code attaches it directly on a Read in that directory, and render-index.sh wiring reports the row NATIVE rather than UNWIRED, which is the check to run. It does not present that as a reason to remove a shim; if it still recommends one, the reason is availability cover for sessions that cannot read AGENTS.md directly, not reachability here. The rest of the move is unchanged: destination before excision, index regenerated, result verified.'
---

/instruction-placement:realign apply IP-002, the billing subtree conventions. This repo has no CLAUDE.md at all: no root one, no .claude/CLAUDE.md, no CLAUDE.local.md. Should we still add the shim beside it?

This branch's findings artifact (branch and Claude Code version both match) lists IP-002 as `proposed`: the Billing module section at `AGENTS.md` lines 52 to 55, destination a nested `AGENTS.md` in `src/billing/`, which holds 23 tracked files and no instruction file. The cited lines still hold that section, and the root `AGENTS.md` carries the rules index.

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
