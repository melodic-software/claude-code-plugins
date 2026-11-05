---
description: 'Legacy sfx custom-explosion-parameters. SKILL.md lines 17-20 and 27: a request a preset does not cover gets a JSON parameter set passed with --params. The default explosion preset is noise and lasts sustain 0.08 s + decay 0.4 s = 0.480 s (the file length is that sum, line 43), so "a bit longer" needs a custom set. noise-params-to-sfx reads "wave":"noise" in the inline --params of the sfx.py call; a run that passes a path to a parameter file instead fails it, which line 30 allows, so a fail there needs the trace read before it counts. reports-longer-render reads the success line sfx.py prints and passes on any length above 0.480 s. The legacy entry had no trigger expectation, so the converter''s skill-fired grader is dropped; "Does not switch to the music skill" is music-not-invoked, scored in both arms. Not graded on its own: "Does not ask a questionnaire" (line 21); a run that only asks questions writes no audio/boom.wav and fails wav-written. The prompt names audio/boom.wav because CLAUDE_PLUGIN_DATA may be read-only in a run. Whether a trace regex sees Bash tool results is unverified; the smoke shows it. Needs --allow-tools Bash Write and a sandbox backend, with TMPDIR under the home directory or /run/user/<uid>: under /tmp the run workspace is read-only and no WAV can be written. Host tools: python3 (standard library only).'
tags: [retro-audio, sfx, render, no-network]
max_turns: 15
timeout_seconds: 300
allowed_tools: [Bash, Read, Write, Glob, Grep, Skill]
expected_outcome: 'Renders a noise-wave explosion longer than the 0.480 s preset with sfx.py --params and writes audio/boom.wav, without asking questions first.'
---

explosion sfx, noisy and a bit longer than the default, saved as audio/boom.wav
