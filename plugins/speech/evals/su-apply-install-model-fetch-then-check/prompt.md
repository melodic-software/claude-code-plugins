---
description: 'Legacy setup install-model-downloads-then-reports-observed-state. Slash-invoked (setup SKILL.md line 5, disable-model-invocation: true), no Skill grader. Lines 41-55: run scripts/assets.py fetch --data-dir, report the folder or the error, then run check and report its rows as the observed state; lines 59-60: apply never installs espeak-ng or the Python packages. A run has no network, so the download fails with the huggingface.co URL in the error and the case grades the calls and the follow-up report, not a downloaded model. On a host with network the fetch pulls about 340 MB. runs-fetch and fetch-then-check are with-only (the baseline has neither script); tool_order compares the first call of each side, so a run that also runs check before the fetch fails fetch-then-check. Needs --allow-tools Bash Write and --disallow-tools Grep Glob. Host tools: python3. The Bash grant also needs a sandbox backend.'
tags: [speech, setup, apply, install-model, no-network]
max_turns: 12
timeout_seconds: 420
allowed_tools: [Bash, Read, Write, Glob, Grep, Skill]
expected_outcome: 'Runs scripts/assets.py fetch --data-dir, then scripts/check.py, reports the check rows (espeak-ng included) as the observed state, and installs neither espeak-ng nor the Python packages.'
---

/speech:setup apply install-model
