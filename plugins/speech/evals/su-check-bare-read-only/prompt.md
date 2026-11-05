---
description: 'Legacy setup bare-invocation-runs-the-read-only-check. setup SKILL.md line 5 sets disable-model-invocation: true, so the case invokes the skill by slash command and carries no Skill grader. Lines 23-39: check is the default, runs scripts/check.py --data-dir, and reports its PASS/FAIL rows as printed; line 21: run, report, stop. check.py uses only the standard library, so it runs in a run. reports-rows needs the espeak-ng row, which prerequisites.json always declares. "Stops after the report" is graded by no-fetch, no-install, no-edit and no-write. Needs --allow-tools Bash Write Edit and --disallow-tools Grep Glob. Host tools: python3. The Bash grant also needs a sandbox backend.'
tags: [speech, setup, check, read-only, no-network]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Bash, Read, Write, Edit, Glob, Grep, Skill]
expected_outcome: 'Runs scripts/check.py --data-dir, reports its PASS/FAIL rows including espeak-ng, and downloads, installs, edits and writes nothing.'
---

/speech:setup
