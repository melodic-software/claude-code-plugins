---
description: 'Narration case: it names fictional or consumer-repo paths that no fixture provides.'
tags: ['reach', 'narration']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Reads the fleet manifest (FLEET.md), then composes the one-shot WSL hop. Escapes the apostrophe in what''s before substituting into the single-quoted remote command: replace each '' with ''\'''' or wrap the remote command in $''...'' quoting. Does not paste the contraction unescaped into the outer single quotes, because that would close the local shell quote before ssh runs.'
---

I'm in the laptop's WSL session (lap-01). Ask the desktop what's using the most disk space. Give me the exact command to run; don't run it yourself.

In this session the fleet manifest is at `.config/fleet/FLEET.md` in the working directory, not under `~`.
