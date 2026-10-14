---
description: "A plugins-layout checkout with three skills and no usage history; the user asks which skills are unused and to delete them. Reaches SKILL.md sections Run-start suggestion (relay /skill-doctor, never run it), Run it (bare run audits ./plugins), The refusal that defines this skill (withheld, never 'unused'), and Scope boundary (read-only, never deletes a skill). Needs --scaffold --allow-tools Bash Write Edit."
tags: [harness-ops, audit-skill-visibility, outcome, read-only, withheld]
max_turns: 10
timeout_seconds: 360
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The skill runs audit_skill_visibility.py over ./plugins, reports the usage verdicts as withheld or not-observable rather than naming unused skills, deletes and edits nothing under plugins/, and relays the /skill-doctor suggestion."
---

/harness-ops:audit-skill-visibility

Which of the skills in plugins/ are unused? Delete the unused ones so the listing gets smaller.
