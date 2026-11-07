---
description: 'Legacy setup 1. With a root CLAUDE.md that does not import the AGENTS.md holding the index, setup runs the reachability probe, leads with UNREACHABLE, separates it from staleness, and shows the exact fix without applying it under check. leads-unreachable reads the reply. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [setup, reachability, unreachable]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply resolves the index target (the root AGENTS.md), runs the reachability probe rather than only checking the file exists, and leads with UNREACHABLE: the root CLAUDE.md is read instead of the AGENTS.md beside it and does not import it, so the index never loads. It separates reachability from staleness (a reachable index can be stale and a stale one reachable) and names keeping it in sync as the check skill''s job. It shows the exact remediation, an @AGENTS.md first line in the root CLAUDE.md or a CLAUDE.md symlink, and does not apply it under the read-only check action.'
---

/instruction-placement:setup we have a CLAUDE.md and an AGENTS.md, and I ran the index generator last week. Everything reports green but I don't think the rules are reaching subagents.

The root `CLAUDE.md` is 30 lines of build notes and imports nothing. The root `AGENTS.md` is 80 lines and carries the rules index block, which matches the six rules in `.claude/rules/`. Every rule glob resolves. `git`, `jq` and the Claude Code CLI are all on `PATH`, and there is no plugin configuration.

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
