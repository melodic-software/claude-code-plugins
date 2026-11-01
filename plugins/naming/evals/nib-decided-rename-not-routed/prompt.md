---
description: "Negative routing case: the new name is already chosen and applied at the definition, so the ask is a reference sweep, not naming. The description excludes it ('Not for an already-decided rename ... That routes to the rename-references sweep', SKILL.md line 2; 'Adjacent skills', lines 228-239). The rename-references skill lives in another plugin and is not loaded, so the case grades only that name-it-better is not invoked, that no candidate generators are spawned, and that the reply lists the three stale files. Expect parity on the reply grader: a no-plugin baseline sweeps too."
tags: [naming, name-it-better, outcome, routing, negative, scaffold, invented]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Agent]
expected_outcome: "No Skill call to naming:name-it-better and no subagent asked for name candidates. The reply lists the stale fetchUser references in src/pages/profile.js, src/components/header.js and README.md with lines, proposes no other name, and edits nothing."
---

I renamed `fetchUser` to `loadUser` in src/users/api.js; that name is final. Before I commit, list every file and line that still says `fetchUser`. Do not edit anything.
