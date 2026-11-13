---
description: 'Legacy apply-cache-line-copies-and-prints-without-writing-settings. The scaffold seeds the run home''s ~/.claude/settings.json with the statusLine the prompt names, and places a byte-identical ~/.claude/context-usage/cache-line.mjs, since the run home''s ~/.claude is read-only in the eval sandbox: copied-script grades the identical-copy branch of step 1. setup SKILL.md lines 204-206 (copy cache-line.mjs; copied-script is arm with-only, a bundled script), 207-215 (find the statusLine in effect), 216-224 (pipe the settings into cache-line.mjs --wire and print it, never write it or compose it by hand; ran-wire is arm with-only), 225-226 (point at the README for what the segment needs and covers), 240-244 (no settings write). Legacy ''needs node on PATH'' is dropped: SKILL now points at README lines 162-181, which say no refreshInterval is needed and the segment covers the main conversation only, and say nothing about node. Legacy ''one quoted --after argument ... keeps padding 2'' is split into wraps-existing-command and keeps-padding. The run''s Claude Code settings may live in a separate config directory, so the seeded file may not be the settings the harness loads; the prompt names the path and the command so a run that reads elsewhere still has them. Host-bound: needs node on PATH for --wire. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail.'
tags: [context-usage, setup, apply, cache-line, must-not, no-network]
max_turns: 16
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Finds ~/.claude/context-usage/cache-line.mjs already current and writes nothing, pipes the settings into cache-line.mjs --wire and prints a statusLine whose command is node ~/.claude/context-usage/cache-line.mjs --after with the existing command single-quoted intact, padding 2 kept; says no refreshInterval is needed and that it covers the main conversation only; no settings write by any route, install or plugin CLI write.'
---

/context-usage:setup apply cache-line

My user settings at ~/.claude/settings.json have a statusLine whose command is `bash -c 'echo "$(git branch --show-current) (dev)"'` with padding 2. Show me the statusLine to paste. Also, what does the segment need to run, and what does it cover?
