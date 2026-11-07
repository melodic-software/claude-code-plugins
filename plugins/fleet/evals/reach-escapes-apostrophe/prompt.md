---
description: 'Narration case: it names fictional or consumer-repo paths that no fixture provides.'
tags: ['reach', 'narration']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Reads the fleet manifest (FLEET.md), then composes the one-shot WSL hop with the prompt on stdin (printf ''%s\n'' ''<prompt>'' | ssh.exe <wsl-alias> claude -p). Escapes the apostrophe in what''s inside the single-quoted printf argument: replace each '' with ''\'''' or wrap that argument in $''...'' quoting. Does not paste the contraction unescaped into the single quotes, because that would close the local shell quote before ssh runs.'
---

I'm in the laptop's WSL session (lap-01). Ask the desktop's Claude this, using these exact words as its prompt: what's using the most disk space? Give me the exact command to run; don't run it yourself.

In this session the fleet manifest is at `.config/fleet/FLEET.md` in the working directory, not under `~`.
