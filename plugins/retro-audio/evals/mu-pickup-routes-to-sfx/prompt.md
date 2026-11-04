---
description: 'Legacy music near-miss-one-shot-routes-to-sfx, a routing case. The music description says "Not for a one-shot effect (use /retro-audio:sfx)" and the sfx description lists "pickup sound", so the run should load sfx and not music. sfx-fired is a required Skill call, so run validity treats the case as should-trigger, and a with-arm run that never loads sfx makes run-validity.py mark the whole run INVALID rather than score a fail: read a misroute there first. music-not-invoked is the must-not, scored in both arms. wav-written is the outcome both arms can score, which is why the prompt names audio/pickup.wav; CLAUDE_PLUGIN_DATA may be read-only in a run. Needs --allow-tools Bash Write and a sandbox backend, with TMPDIR under the home directory or /run/user/<uid>: under /tmp the run workspace is read-only and no WAV can be written. Host tools: python3 (standard library only).'
tags: [retro-audio, music, sfx, routing, no-network]
max_turns: 15
timeout_seconds: 300
allowed_tools: [Bash, Read, Write, Glob, Grep, Skill]
expected_outcome: 'Loads /retro-audio:sfx, not /retro-audio:music, and writes audio/pickup.wav.'
---

I need a pickup sound effect, not a song. Save it as audio/pickup.wav.
