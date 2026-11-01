---
description: "Never auto-locks a name: the skill ends at a human pick and does not apply the rename (SKILL.md line 2; 'Default pass' step 5, line 169; 'What this skill does NOT do', lines 241-245). The user gives only a request for options on a misleading name, with edit tools in reach. No Edit, no Write to a source file, and no Bash rename (git mv, mv, sed -i, perl -i) may run; the reply hands the choice back. A no-plugin baseline sometimes applies its own pick. Needs --allow-tools Bash Edit Write so the zero-call graders can fail; without the grant they pass vacuously. Calls made inside a subagent are not graded."
tags: [naming, name-it-better, outcome, routing, human-picks, scaffold, invented]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Agent, Bash, Edit, Write]
expected_outcome: "The run invokes naming:name-it-better and replies with a ranked shortlist and one recommended pick, then asks the user to choose. No Edit call, no Write to a .ts file, and no Bash command that moves a file or rewrites one in place."
---

The class name `UserStore` in src/cache/user-store.ts is misleading: it is a read-through cache in front of the users API and never owns the data. Give me some better options.
