---
description: 'Legacy narrate voice-and-speed-are-passed-through. narrate SKILL.md lines 24-29: --out defaults to the script file''s folder, bf_/bm_ voices speak British English and scripts/kokoro-assets.json pins bm_daniel, bm_fable, bm_george and bm_lewis, and --speed runs 0.5 to 2.0 with 1.0 the default. The voice, speed and output graders read the narrate.py call, so they are with-only; the render itself fails in a run (no numpy, onnxruntime, espeak-ng or model) and is not graded. Needs --scaffold --allow-tools Bash Write, --disallow-tools Grep Glob, and hooks/install-python-deps.sh stubbed to exit 0 in the smoke copy. Host tools: python3. The prompt does not name the skill, so narrate-fired is the trigger indicator; a with-arm run that never loads narrate makes run-validity.py mark the leg INVALID. Only no-install and no-fetch are scored; read the voice, speed and output folder from the with-only indicators, not from the score. The Bash grant also needs a sandbox backend.'
tags: [speech, narrate, no-network]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Bash, Read, Write, Glob, Grep, Skill]
expected_outcome: 'Runs narrate.py with a pinned bm_ voice and a --speed from 0.5 up to but not including 1.0, writing beside docs/script.txt (no --out, or --out docs), and installs or downloads nothing.'
---

Narrate docs/script.txt with a British male voice, a little slower than normal.
