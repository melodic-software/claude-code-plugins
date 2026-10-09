---
description: "Core loop: a named session, a snapshot for element refs, a click by ref (not a CSS selector), and closing the session"
tags: [playwright, core]
runs: 3
max_turns: 15
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply's playwright-cli commands all carry one named session (-s=<name>) from open through close, take a snapshot before clicking, click by a snapshot ref such as e42 rather than a CSS or text selector, and close the session"
---

With playwright-cli, I want to click the "Add to cart" button on the home page of my app at http://localhost:3000 and screenshot what happens. Don't run anything: give me the exact commands, in order, in one bash code block.
