---
tags: ['reach']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Starts a named headless receiver: claude.exe -p -n <name> --settings with crossSessionInbound set to accept, with standing instructions saying what to do with messages and when to stop. Handles the JSON quoting inside an outer single-quoted remote command (escaped double quotes). States that the receiver lives only as long as its turn; for a session that must stay up, offers a background session (claude --bg --name, which needs a trusted directory) or --resume for durable multi-turn work. Does not use --bare for a receiver, since a bare session binds no inbox socket.'
---

I'm in the laptop's WSL session (lap-01). Start a Claude session on the desktop's Windows side that other sessions can keep sending messages to. Give me the exact command to run; don't run it yourself.
