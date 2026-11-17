---
description: "check with no spelling record and no typos config. setup SKILL.md check step 3: a none row is INFO unresolved, the opt-out by design; the hooks run only the typos adapter, and a spelling record runs only through /toolchain:lint and /toolchain:check, written by /toolchain:setup apply spelling. Replaces su-check-absent-config-not-inert, whose claim (the check runs with or without a config) the lint entry's config gate retired. The file_exists graders catch a record or typos config written. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [spelling, setup, check, read-only, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No record or config written, no Write or Edit. The lint concern is unresolved INFO; not broken; the way forward is a typos config for the hooks, or a spelling record for /toolchain:lint."
---

/spelling:setup check

My commits never get spell-checked in this repo. Is spelling broken?
