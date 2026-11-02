---
description: "Environment probe for the browser lane's MCP path, tagged browser-mcp-probe only: records whether the pinned Playwright MCP server starts, Chromium opens a file, localhost and public page, a screenshot is written, and the eval directory stays hidden. Each grader records one fact, so the score is not a quality measure"
tags: [browser-mcp-probe]
plugins: ["pw-mcp"]
runs: 1
max_turns: 30
timeout_seconds: 900
allowed_tools:
  - Read
  - mcp__plugin_pw-mcp_playwright__browser_navigate
  - mcp__plugin_pw-mcp_playwright__browser_take_screenshot
  - mcp__plugin_pw-mcp_playwright__browser_close
expected_outcome: "Runs every step in probe/steps.txt once, as written, through the Playwright MCP tools and Read, and replies PROBE DONE"
---

This is an environment check, not a task to solve. The file `probe/steps.txt` in the working directory lists one step per line.

1. Read `probe/steps.txt`.
2. Do each line in order, exactly once, exactly as written:
   - `NAVIGATE <url>` is one `browser_navigate` call with that `url`;
   - `SCREENSHOT <name>` is one `browser_take_screenshot` call with that `filename`;
   - `CLOSE` is one `browser_close` call;
   - `READ <path>` is one Read call on that path.
3. Keep going when a step fails or is refused. Do not retry, fix, change or add to any step, and make no other call.

When every line is done, reply with exactly `PROBE DONE` and nothing else.
