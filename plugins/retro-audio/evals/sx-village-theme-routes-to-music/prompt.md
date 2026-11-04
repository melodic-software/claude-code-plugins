---
description: 'Legacy sfx near-miss-song-routes-to-music, a routing case. The sfx description says "Not for a song or loop (use /retro-audio:music)" and the music description lists "retro game loop", so the run should load music and not sfx. music-fired is a required Skill call, so run validity treats the case as should-trigger, and a with-arm run that never loads music makes run-validity.py mark the whole run INVALID rather than score a fail: read a misroute there first. sfx-not-invoked is the must-not, scored in both arms. wav-written is the outcome both arms can score, which is why the prompt names audio/village.wav; CLAUDE_PLUGIN_DATA may be read-only in a run. Needs --allow-tools Bash Write and a sandbox backend, with TMPDIR under the home directory or /run/user/<uid>: under /tmp the run workspace is read-only and no WAV can be written. Host tools: python3 (standard library only).'
tags: [retro-audio, sfx, music, routing, no-network]
max_turns: 15
timeout_seconds: 300
allowed_tools: [Bash, Read, Write, Glob, Grep, Skill]
expected_outcome: 'Loads /retro-audio:music, not /retro-audio:sfx, and writes audio/village.wav.'
---

write a looping 8-bit village theme, about four bars, saved as audio/village.wav
