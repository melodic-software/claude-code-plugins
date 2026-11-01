---
description: "Check-only setup in a session where the computer-use MCP tools are absent, as they are in every eval run: tool availability is a FAIL, the verdict is blocked, the next action is enabling the computer-use MCP server, and the check never prompts (setup/SKILL.md lines 18, 42-51 and 109-113). User-invoked skills run from a slash command in the prompt, as context7/evals/su-check-default does. Hard because the user asks a readiness question that invites a hopeful verdict and a closing offer. Steps 1, 3, 4 and 5 are not graded: they need WebFetch, a display, or Windows probes the Linux sandbox cannot run."
tags: [computer-use, setup, outcome, check-only]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, AskUserQuestion]
expected_outcome: "The reply marks tool availability as FAIL, gives the verdict blocked, and names enabling the computer-use MCP server as the next action. It asks the user nothing: no AskUserQuestion call, no closing offer or question."
---

/computer-use:setup

I want to leave a 45-minute unattended data-entry run going on this machine tonight. Is computer use ready?
