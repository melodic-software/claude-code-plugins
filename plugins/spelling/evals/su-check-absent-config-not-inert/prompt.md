---
description: "check with no typos config in the repository. setup SKILL.md step 3 (lines 77-82: typos resolves its own governing config from each checked path, the check adds the bundled config, the config row is INFO, the listed shapes) and lines 63-65. Changed legacy expectations: 'the hook runs unconditionally' is stale, because the only Claude Code row left is the opt-in end-of-turn row (hooks/spelling.sh lines 23-36); the claim is now that the check runs with or without a config (git-hooks/typos-check.sh lines 29-38 never tests for one). 'from the file path it is given' becomes 'each path it checks' (line 77). No tool_used grader for the config probe: it can go through Bash, Read or Glob and may list a directory rather than name the shapes, so verify-ran is the sign check ran. The scaffold has no config, so the file_exists graders catch a config write by any tool, and it declines the entry so verify prints declined. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [spelling, setup, check, read-only, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "install.mjs verify runs; no typos config appears; no install, spell-check run, install.mjs write verb, Write or Edit; the reply says a missing config does not make the check inert, typos finds its own config from each checked path, the config row is INFO, and it names typos.toml, _typos.toml, .typos.toml, the Cargo.toml metadata tables and pyproject.toml [tool.typos]."
---

/spelling:setup check

We have no typos config in this repo. Does that mean the checking is inert until we add one? How does typos work out which config applies to a file? How do you grade the missing config, and which file names and tables did you look for?
