---
description: "Default after open: a flow on a logged-in site loads the saved per-site login with state-load right after open, and never saves one"
tags: [playwright, login-state]
runs: 3
max_turns: 15
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply gives playwright-cli commands that open a named session, then run state-load on the saved github.json under the playwright-cli state directory, then go to the settings page; it never runs state-save"
---

Using playwright-cli, I need to check what the Settings tab of https://github.com/acme-example/widgets shows. That page only appears when I'm signed in as the repo owner. Don't run anything: give me the exact commands, in order, in one bash code block.
