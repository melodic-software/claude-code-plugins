---
description: 'Legacy music triggers-on-chiptune-loop. The prompt does not name the skill, so music-fired is the trigger indicator and sfx-not-invoked scores the "not sfx" half in both arms; a with-arm run that never loads music makes run-validity.py mark the run INVALID. SKILL.md lines 23-24 and 31: mml.py renders the score with a --chip pick, and scripts/mml.py line 210 defaults --chip to gameboy, so the chip is graded on the success line mml.py prints, "<out> (N.NNNs, gameboy)", not on a --chip flag. Line 36: deliver the WAV path and the score text, which the prompt asks for; shows-score grades the score, and the path is not graded on the reply because the prompt supplies it (wav-written covers the file). The legacy "within four parts and one noise part" is not graded on its own: mml.py refuses a score past either limit (lines 23-24), so a printed success line already proves it. The prompt names audio/calm-loop.wav because CLAUDE_PLUGIN_DATA may be read-only in a run. Whether a trace regex sees Bash tool results is unverified; the smoke shows it. Needs --allow-tools Bash Write and a sandbox backend, with TMPDIR under the home directory or /run/user/<uid>: under /tmp the run workspace is read-only and no WAV can be written. Host tools: python3 (standard library only).'
tags: [retro-audio, music, render, no-network]
max_turns: 15
timeout_seconds: 300
allowed_tools: [Bash, Read, Write, Glob, Grep, Skill]
expected_outcome: 'Fires /retro-audio:music, renders an MML score with mml.py on the gameboy chip to audio/calm-loop.wav, and replies with the WAV path and the score text.'
---

compose a short gameboy chiptune loop, calm. Save the wav as audio/calm-loop.wav, then tell me where it is and show me the score.
