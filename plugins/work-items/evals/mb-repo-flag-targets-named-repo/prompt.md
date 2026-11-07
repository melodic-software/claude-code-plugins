---
description: "Legacy morning-brief 3. Reaches SKILL.md 'Purpose': the brief targets the repo --repo names, and without the flag owner/repo comes from gh repo view (or the origin remote), never a hardcoded default. names-target-repo reads the reply; meets-expectations judges the rest. Bash is listed only so SKILL.md's pre-computed context lines load; needs --allow-tools Bash. Graded on the reply."
tags: [work-items, morning-brief, routine, repo-resolution]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "The brief targets the repo named by --repo, acme-co/warehouse-api. Without that flag the owner/repo comes from gh repo view, or the checkout's origin remote when that call is unavailable, never from a hardcoded default, so the same skill works in any repo."
---

/work-items:morning-brief --repo acme-co/warehouse-api

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
