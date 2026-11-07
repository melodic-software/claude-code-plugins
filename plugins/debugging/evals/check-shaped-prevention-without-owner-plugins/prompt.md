---
description: "Phase 6 Prevention with a check-shaped answer and neither owner plugin installed: the post-mortem says a deterministic check for float math on money would have caught the bug, files it with the issue tracker as its own prevention finding (drafted, since the run has no network), names neither /corrections:codify nor /session-flow:retro as the destination, does not recast it as an architectural finding (the regression test sits at a valid seam), and builds no check. Scaffold: a git repository whose AGENTS.md bans float money math, with the Decimal fix and its test committed. Needs --scaffold --allow-tools Bash Edit Write"
tags: [debug, converted, scaffold, no-network]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write]
expected_outcome: "The post-mortem states that a deterministic check would have caught the banned float math, files that check with the issue tracker as its own prevention finding, does not name /corrections:codify or /session-flow:retro as where it goes, does not recast it as an architectural finding, and writes or edits no lint config, hook or analyzer rule"
---

/debugging:debug is done: invoice totals were off by a cent because one module rounded with float math the repo bans for money. The regression test sits at the module's public seam and the fix is in. Write the post-mortem. Neither the corrections nor the session-flow plugin is installed.
