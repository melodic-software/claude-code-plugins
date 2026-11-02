---
description: 'Narration case: it names fictional or consumer-repo paths that no fixture provides.'
tags: ['reach', 'narration']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Reads ~/.config/fleet/FLEET.md to resolve the host, port and account instead of guessing them. Composes a one-shot headless turn over the WSL hop: ssh -p 2222 <wsl-user>@<host> ''claude -p "..." < /dev/null''. Keeps the stdin redirect. Notes that the turn runs under the desktop''s own Claude account and that it prompts under auto mode.'
---

I'm in the laptop's WSL session (lap-01). Ask the desktop to tell me how much free space is on its D drive. Give me the exact command to run; don't run it yourself.
