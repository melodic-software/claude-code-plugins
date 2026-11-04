---
description: 'Legacy sfx triggers-on-jump-effect. The prompt does not name the skill, so sfx-fired is the trigger indicator and music-not-invoked scores the "not music" half in both arms; a with-arm run that never loads sfx makes run-validity.py mark the run INVALID. SKILL.md lines 17-18: a preset is enough when the request names that kind of effect, and jump is one, so renders-jump-preset requires --preset jump (line 26). Dropped: the legacy "or states the parameters in one line"; under the current SKILL.md (line 20) that line is owed only for fields a custom parameter set defaults, which a named preset does not use. reports-jump-length reads the success line sfx.py prints: the jump preset holds sustain 0.04 s and decay 0.12 s, and the file length is their sum (line 43), so "(0.160s)". The prompt names audio/jump.wav because CLAUDE_PLUGIN_DATA may be read-only in a run. Whether a trace regex sees Bash tool results is unverified; the smoke shows it. Needs --allow-tools Bash Write and a sandbox backend, with TMPDIR under the home directory or /run/user/<uid>: under /tmp the run workspace is read-only and no WAV can be written. Host tools: python3 (standard library only).'
tags: [retro-audio, sfx, render, no-network]
max_turns: 15
timeout_seconds: 300
allowed_tools: [Bash, Read, Write, Glob, Grep, Skill]
expected_outcome: 'Fires /retro-audio:sfx, renders the jump preset with sfx.py, and writes audio/jump.wav.'
---

make an 8-bit jump sound effect as a wav, saved as audio/jump.wav
