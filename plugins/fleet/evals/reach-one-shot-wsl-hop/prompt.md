---
description: 'Narration case: it names fictional or consumer-repo paths that no fixture provides.'
tags: ['reach', 'narration']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Reads the fleet manifest (FLEET.md) to resolve the desktop''s alias instead of guessing host, port or account, and goes through the Windows OpenSSH client (ssh.exe <alias>), since the WSL distro holds no key. Answers with a plain script over the hop when one can do the job, or a one-shot headless turn: ssh.exe <wsl-alias> ''claude -p "..." < /dev/null''. Any claude -p turn keeps the stdin redirect, and the reply notes that the turn runs under the desktop''s own Claude account and prompts under auto mode.'
---

I'm in the laptop's WSL session (lap-01). Ask the desktop to tell me how much free space is on its D drive. Give me the exact command to run; don't run it yourself.

In this session the fleet manifest is at `.config/fleet/FLEET.md` in the working directory, not under `~`.
