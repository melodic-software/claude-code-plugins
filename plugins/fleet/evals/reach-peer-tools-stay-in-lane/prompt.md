---
tags: ['reach']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Does NOT call ListAgents or SendMessage locally and does not claim they reach the desktop. Explains that accounts are per lane, so the peer tools see only this lane. Starts a turn inside the desktop''s lane over its WSL hop (ssh.exe desk-wsl): R2 for the desktop''s WSL lane, the default agent lane, and for its Windows lane R3, a claude.exe turn started by absolute path from a Windows-side scratch directory. That turn''s own peer tools list and then message the sessions. Lists first and messages a name from that list. May load reference/relay.md.'
---

I'm in the laptop's WSL session (lap-01). List the Claude sessions running on the desktop and send a message to the one in the sandbox checkout. Give me the exact command to run; don't run it yourself.

In this session the fleet manifest is at `.config/fleet/FLEET.md` in the working directory, not under `~`.
