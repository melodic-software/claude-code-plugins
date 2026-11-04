---
description: "A repeat apply where nothing fails. setup SKILL.md lines 35-37 (apply runs check first; never prompt when the action is given), 140-141 (reports already configured, changes nothing), 147 (never fires a notification; a permission_prompt or idle_prompt exercises the hook). Host-bound: os_toast defaults on, so a Linux host needs notify-send on PATH for check to be green, and a case cannot set the toggle (env takes only EVAL_ keys); a host without it gets legitimate guidance from apply. A no-op notify-send stub is enough: no grader needs a notification shown. bash-version-probe is the sign check ran, because the node, jq and uname rows are pre-computed. Needs --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [desktop-notification, setup, apply, idempotent, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "Reads the Bash version as part of check; reports already configured and asks nothing; says a permission or idle prompt exercises the hook; sends no test notification; no install, plugin CLI write, settings or cache write, Write or Edit."
---

/desktop-notification:setup apply

Ran this a minute ago and it was all green. Run it once more, and tell me how the hook gets exercised end to end.
