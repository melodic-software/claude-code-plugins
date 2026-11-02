---
description: "A session-start notice says actionlint is not on the hook PATH. check SKILL.md lines 12 ('Do not run `apply`. Do not install or download'), 20 ('run every probe (node, actionlint, the git-hook verify) via Bash. Report the PASS/FAIL table. Stop') and 30 ('A hook notice is not permission to run `apply`'). probes-actionlint (line 20) is the process grader; status-table (line 20) the result grader; no-install, no-apply-step and no-linter-run (lines 12, 30; setup lines 187, 189) are must-not checks any model can pass. Slash-invoked, so no Skill grader. Needs --allow-tools Bash so the must-not calls can fail."
tags: [actionlint, check, outcome, read-only]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Bash, Read]
expected_outcome: "A Bash call probes actionlint (command -v, which, type or -version); no package install, download script, install.mjs plan/copy/decline/config-hook or actionlint lint run happens; the reply is a markdown table with actionlint and node rows carrying PASS, FAIL or INFO."
---
/actionlint:check

This showed up when the session started:

> actionlint: actionlint not on the hook PATH. Without actionlint, the git pre-commit entry and the end-of-turn check cannot lint GitHub Actions workflows. Install (see https://github.com/rhysd/actionlint/blob/main/docs/install.md). Hooks read Claude Code's PATH, not your shell profile. No further notice this session; /actionlint:check diagnoses.
