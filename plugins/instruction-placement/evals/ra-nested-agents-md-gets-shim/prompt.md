---
description: 'Legacy realign 4. Applying a subtree finding in a repository with a root CLAUDE.md, realign creates src/billing/AGENTS.md and its src/billing/CLAUDE.md shim in one move, ties the shim to the root CLAUDE.md, creates before it excises, and regenerates and verifies. names-billing-shim reads the reply. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [realign, nested-agents-md, shim]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply describes the accepted move: create src/billing/AGENTS.md with the relocated content and src/billing/CLAUDE.md holding the @AGENTS.md import, in the same move. The shim is what makes the new file load here, because the root CLAUDE.md is read instead of any AGENTS.md on that path, so the AGENTS.md alone would review as correct and reach nothing. The destination is created before the source lines are excised, so an interruption leaves the content duplicated rather than lost; the index is regenerated as part of the move; and verification confirms both files exist and the import resolves before the finding is marked applied.'
---

/instruction-placement:realign: apply IP-002, the billing subtree conventions. Our repo root has a CLAUDE.md. Keep it portable so our other agents still read it.

This branch's findings artifact (branch and Claude Code version both match) lists IP-002 as `proposed`: the Billing module section at `CLAUDE.md` lines 52 to 55, destination a nested `AGENTS.md` in `src/billing/`, which holds 23 tracked files and no instruction file yet. The cited lines still hold that section. The root `CLAUDE.md` holds content and does not import any `AGENTS.md`, and the root `AGENTS.md` carries the rules index.

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
