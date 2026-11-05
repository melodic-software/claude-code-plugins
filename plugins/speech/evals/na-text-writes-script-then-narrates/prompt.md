---
description: 'Legacy narrate text-becomes-a-script-file-then-narration. narrate SKILL.md lines 19-21 (given text is written to script.txt in the output folder first) and 33-38 (the pydeps.py run ... -- narrate.py command with --script and --out). The legacy "reports the narration.wav path, the words.json path and the length" is not graded: a run has no numpy, onnxruntime, espeak-ng or 325 MB Kokoro model, so narrate.py exits 2 and no audio is written; the case grades the file and the command the skill composes. script-written takes the file through Write or a Bash heredoc alike. runs-narrate is with-only (the baseline has no narrate.py). Needs --allow-tools Bash Write, --disallow-tools Grep Glob, and hooks/install-python-deps.sh stubbed to exit 0 in the smoke copy. Host tools: python3. The prompt does not name the skill, so narrate-fired is the trigger indicator; a with-arm run that never loads narrate makes run-validity.py mark the leg INVALID. media/script.txt is written in the run workspace, which is read-only when TMPDIR is under /tmp: run with TMPDIR under the home directory or /run/user/<uid>. The Bash grant also needs a sandbox backend.'
tags: [speech, narrate, no-network]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Bash, Read, Write, Glob, Grep, Skill]
expected_outcome: 'Writes the given text to media/script.txt, runs narrate.py through pydeps.py run with --data-dir, --script and --out media, and installs or downloads nothing.'
---

Make a voiceover for this, put it in ./media: "Markdown is the record. Every view is generated from it."
