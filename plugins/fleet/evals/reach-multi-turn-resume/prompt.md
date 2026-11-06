---
tags: ['reach']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Recognizes this needs more than one turn. First call either chooses the id with claude -p --session-id <uuid> or reads session_id from claude -p --output-format json; the follow-up uses claude -p --resume <id> over the same host and lane. States that the id belongs to that machine and account and does not travel.'
---

I'm in the laptop's WSL session (lap-01). Have desk-01 read its provisioning runbook, then ask it a follow-up about what it found. Give me the exact command to run; don't run it yourself, and run no command or file read on this host to fill in a value: use a placeholder where one is unknown.

In this session the fleet manifest is at `.config/fleet/FLEET.md` in the working directory, not under `~`.
