---
description: 'Bare specify proposes and writes nothing. specify SKILL.md "Bare: propose" gives each candidate as Promise, Harm, Tool and Folder (a formal-<area> folder under skills_dir) and stops before anything is written; its Boundaries section installs no tool. Host tools: node.'
tags: [formal-verification, specify, bare, read-only]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Bash, Read, Write, Edit, Glob, Grep, Skill]
expected_outcome: 'Proposes at least one promise with its harm, its tool and the formal-<area> folder create would write, and writes, edits and installs nothing.'
---

/formal-verification:specify
