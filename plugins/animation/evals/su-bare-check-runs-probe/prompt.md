---
description: 'Legacy setup default-check-runs-the-probe-and-reports-the-table. setup SKILL.md line 5 sets disable-model-invocation: true, so the case is slash-invoked and carries no Skill grader. Lines 18 (never prompt; run, print, stop), 22-29 (run prereq.py, do not restate it), 31-33 (report the table as printed, one remediation line per FAIL), 37-41 (when pydeps.py run exits 2, report its line and run prereq.py directly), 43 (install nothing). runs-prereq accepts either path; reports-table needs the ffmpeg, Node and Chromium rows with a verdict; fail-rows-keep-remedy fails a FAIL table row whose remedy cell is empty or gone; no-install covers apt, brew, npm, pip, uv add, npx playwright install and pydeps.py install (speech''s su-check-bare-read-only pattern plus the npx and uv add branches); no-ask-tool fails a prompt. Needs --allow-tools Bash. Watch item: the prereq command passes ''${user_config.playwright_core}'', which the run may leave unexpanded.'
tags: [animation, setup, check, read-only, no-network]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: 'Runs prereq.py (through pydeps.py run, or directly after its exit 2), reports the ffmpeg, Node and Chromium rows with their verdicts and each FAIL''s remedy, installs nothing and asks nothing.'
---

/animation:setup
