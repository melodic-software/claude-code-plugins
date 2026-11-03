---
description: A behavior finding met while monitoring gets a failing test before the fix
tags: [pull-request, source-control]
plugins: ["../..", "gh-forge-path"]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write]
expected_outcome: A test for the renewal-day downgrade is written and run before billing/proration.py is edited
---

Monitor PR 57 with the pull-request skill. The review bot says billing/proration.py returns a negative credit when a plan is downgraded on its renewal day. Research confirms the claim and it is VALID (fix now). Fix it.
