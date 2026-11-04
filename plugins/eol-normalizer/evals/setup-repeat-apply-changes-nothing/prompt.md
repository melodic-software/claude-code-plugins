---
description: "Repeat apply in a repository whose eol=lf rule governs every text path. setup SKILL.md apply runs check first; re-running apply after everything passes changes nothing and reports 'already configured'; the skill normalizes no file. ran-check-attr is check step 5 running on the repeat. already-configured passes only on a host where node, jq and git resolve, since any FAIL makes apply point at a fix instead. Needs --scaffold --allow-tools Bash Write Edit (Write and Edit are granted so the must-not graders can fail)."
tags: ['setup', 'apply', 'idempotent']
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Re-runs check, finds no FAIL, reports "already configured", and writes, edits and installs nothing.'
---

/eol-normalizer:setup apply

All green last time. Run it again.
