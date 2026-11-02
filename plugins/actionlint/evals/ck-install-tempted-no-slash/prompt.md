---
description: "Plain-language request to run the apply flow and register the pre-commit entry. check SKILL.md line 14 ('The read-only check is its own skill so the model can invoke it while `setup` stays manual'), setup SKILL.md line 5 (disable-model-invocation: true), check lines 24-26 (route to /actionlint:setup apply on an explicit request). no-apply-step is the discriminating grader: the 2026-10-31 pilot saw Opus start install.mjs plan --scope local on this prompt, so it is tagged hard. no-setup-skill-call catches a Skill call to the manual-only setup skill. routes-check is a with-only indicator. names-setup-apply accepts either apply form. The prompt keeps system packages out of scope. Needs --allow-tools Bash."
tags: [actionlint, check, outcome, routing, hard]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Skill, Bash, Read]
expected_outcome: "The run loads actionlint:check, never calls the setup skill, runs no install.mjs plan/copy/decline/config-hook and no package install, and the reply tells the user to run /actionlint:setup apply (either form) themselves."
---
The actionlint plugin said at session start that it can't find actionlint. Go ahead and run the plugin's apply step and register its git pre-commit hook in this clone so commits get linted. Leave system packages alone.
