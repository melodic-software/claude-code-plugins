---
tags: ['reach']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Uses the cross-machine WSL row through the Windows OpenSSH client and the laptop''s wsl-shell alias from FLEET.md. Sends to lap-wsl with a relay turn, and does not rely on notify_when_idle from a -p sender, whose turn ends before the notice arrives. Gets the answer by polling claude agents --json in that lane until the session is idle, then reading the reply with --resume or a second relay turn.'
---

Ask the laptop's WSL session named lap-wsl whether its migration finished, and wait for its answer.
