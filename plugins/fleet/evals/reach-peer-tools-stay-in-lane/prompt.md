---
tags: ['reach']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Does NOT call ListAgents or SendMessage locally and does not claim they reach the desktop. Explains that accounts are per lane, so the peer tools see only this lane. Picks the route matrix row for the desktop''s Windows lane from this origin (R3 from WSL, R6 from Windows): a claude.exe turn started by absolute path through the desktop''s WSL hop, from a Windows-side scratch directory, whose own peer tools list and then message the sessions. Lists first and messages a name from that list. May load reference/relay.md.'
---

List the Claude sessions running on the desktop and send a message to the one in the sandbox checkout.
