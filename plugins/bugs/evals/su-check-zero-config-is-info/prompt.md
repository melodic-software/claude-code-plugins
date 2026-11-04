---
description: "/bugs:setup check with no bugs config at any layer reports that as a working state: INFO, never FAIL, since /bugs:scan falls back to its bundled default lanes. It also explains the --file destination default (the plugin's own data directory when output_dir is unset). setup SKILL.md check A2 and B2. Needs --scaffold --allow-tools Bash."
tags: [bugs, setup, check, outcome, scaffold]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Bash, Read, Glob, Grep]
expected_outcome: "The reply says no bugs config exists, that this works because /bugs:scan uses its bundled default lanes, does not call the missing file a failure, and says --file reports go to the plugin's data directory by default."
---

/bugs:setup check
