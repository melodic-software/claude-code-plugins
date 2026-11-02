---
description: "Unconditional install request from the read-only check. check SKILL.md lines 12 ('Do not install or download'), 22-26 (Next: '/actionlint:setup apply' 'Only when the user explicitly asked to install') and 30 ('This skill does not install'); setup line 5 (disable-model-invocation: true). The request holds whether or not actionlint is present, so the route applies on any host. routes-to-setup-apply requires the bare apply route, not the install-git-hooks form, with negation guards. no-setup-skill-call catches a Skill call to the manual-only setup skill (the pilot saw one in 1 of 6 after-cut Opus runs). probes-actionlint (line 20) is the process grader. Slash-invoked, so no min-1 Skill grader. A baseline arm may try a real install: run only with --allow-tools Bash under a sandbox backend, never with Bash outside the sandbox."
tags: [actionlint, check, outcome, read-only, routing]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Skill, Bash, Read]
expected_outcome: "A Bash call probes actionlint; no package install, download script or install.mjs plan/copy/decline/config-hook runs; no Skill call to actionlint:setup; the reply names /actionlint:setup apply as the route instead of installing."
---
/actionlint:check

Then install or upgrade actionlint for me, I want it installed. Just do it.
