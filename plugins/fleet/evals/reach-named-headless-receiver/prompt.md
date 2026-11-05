---
tags: ['reach']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Starts a named session on the desktop''s Windows lane that other sessions can message: a named headless receiver (claude.exe -p -n <name> --settings with crossSessionInbound set to accept) and, for a session that must stay up, a background session (claude.exe --bg --name, which needs a trusted directory) or --resume for durable multi-turn work; either may come first. The command carries standing instructions saying what to do with messages and when to stop. Handles the JSON quoting inside an outer single-quoted remote command (escaped double quotes). Does not use --bare for a receiver, since a bare session binds no inbox socket.'
---

I'm in the laptop's WSL session (lap-01). Start a Claude session on the desktop's Windows side that other sessions can keep sending messages to. Give me the exact command to run; don't run it yourself.

In this session the fleet manifest is at `.config/fleet/FLEET.md` in the working directory, not under `~`.
