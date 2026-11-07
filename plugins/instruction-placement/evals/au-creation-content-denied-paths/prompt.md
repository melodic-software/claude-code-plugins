---
description: 'Legacy audit 6. Asked to scope a new-service checklist to services/**, audit denies the paths: destination because a path-scoped rule is not in context before a new file is created, and offers a services/ subtree AGENTS.md with its CLAUDE.md shim, or staying put. subtree-destination reads the reply. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [audit, creation-governing, subtree]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply identifies the section as creation-governing. Before Claude Code 2.1.288 a path-scoped rule fired only on a Read of a matching file, so creating a new file never fired it, and from 2.1.288 a Write fires it only after the file is written; either way the rule may be absent when a new service is made. It denies the path-scoped destination specifically, not the candidate, and offers a subtree destination (services/AGENTS.md with a services/CLAUDE.md @AGENTS.md shim, which this repository needs because its root CLAUDE.md is read instead of any AGENTS.md on that path) or staying put, stating the trigger timing as the reason.'
---

/instruction-placement:audit: the 'New service checklist' section here says what every new service must ship with. Scope it to services/**. (Our repo root has a CLAUDE.md that imports AGENTS.md.)

The root `AGENTS.md` is a 55-line engineering handbook. Lines 35 to 38 read:

```markdown
## New service checklist

Every new service under `services/` must ship with a health endpoint, a Dockerfile, and an entry in
the deployment manifest before it is merged.
```

The root `CLAUDE.md` is the single line `@AGENTS.md`. `services/` holds three services (`billing`, `search`, `notify`) and 74 tracked files, and has no `AGENTS.md` or `CLAUDE.md` of its own. The running Claude Code is 2.1.319.

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
