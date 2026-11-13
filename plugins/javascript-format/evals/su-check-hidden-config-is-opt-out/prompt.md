---
description: "check in a repository whose only Biome file is a hidden .biome.json. setup SKILL.md check step 4 (lines 70-76: the hook records the topmost governing config on the walk from the edited file's directory to the repo root, the hidden dotted variants are intentionally excluded, and no governing config is INFO, the opt-out by design, so the plugin is inert) and step 3 (lines 62-63: a missing binary is FAIL only while a Biome config governs the repo; the SessionStart probe may still report it, lines 68-69) and apply's last bullet (lines 190-191: a minimal biome.json only when explicitly asked). The legacy prompt said no config exists anywhere; the scaffold's .biome.json and the prompt's questions raise the dotted and walk expectations, which that prompt never did. The clone declined the entry so verify prints declined. The file_exists graders catch a config write by any tool. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [javascript-format, setup, check, read-only, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No biome.json or biome.jsonc is written and none is offered; no install, Write or Edit; the reply says the plugin is not broken: no governing config is INFO, the opt-out by design; .biome.json does not count; the topmost config on the walk governs; and a missing biome is not a FAIL while no config governs."
---

/javascript-format:setup check

This repo has a hidden .biome.json but no biome.json, and JavaScript files are never rewritten. Is the plugin broken? Why doesn't that file count? If we later add one config at the root and another in a subdirectory, which one governs a file under the subdirectory? And if biome were missing from this repo, would check call that a FAIL?
