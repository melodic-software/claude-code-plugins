---
description: 'Legacy music pasted-mml-is-rendered. SKILL.md line 31: the pasted score goes to mml.py as the quoted score argument, with --chip nes because the user named it (line 23). The legacy entry had no trigger expectation, so the converter''s skill-fired grader is dropped. passes-score-to-mml reads the pasted notes in the mml.py command, so a run that copies them into a --score file fails it; SKILL.md shows only the inline form. reports-nes-length reads the success line mml.py prints: four eighth notes at t140 last 4 x (60/140) x (4/8) = 0.857 s (line 45: l8 is an eighth), so "(0.857s, nes)" proves the chip and the unchanged rhythm. The prompt names audio/arpeggio.wav because CLAUDE_PLUGIN_DATA may be read-only in a run. Whether a trace regex sees Bash tool results is unverified; the smoke shows it. Needs --allow-tools Bash Write and a sandbox backend, with TMPDIR under the home directory or /run/user/<uid>: under /tmp the run workspace is read-only and no WAV can be written. Host tools: python3 (standard library only).'
tags: [retro-audio, music, render, no-network]
max_turns: 15
timeout_seconds: 300
allowed_tools: [Bash, Read, Write, Glob, Grep, Skill]
expected_outcome: 'Passes the pasted score unchanged to mml.py with --chip nes and writes audio/arpeggio.wav.'
---

render this MML to wav on the NES chip and save it as audio/arpeggio.wav: t140 o4 l8 c e g > c
