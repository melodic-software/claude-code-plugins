---
description: "check in a repository whose only Biome file is a hidden .biome.json. setup SKILL.md check step 3 (the --resolve rows read none, INFO unresolved, the opt-out by design, so the plugin is inert; a missing binary is a FAIL only on a row the adapter resolved; adapters.sh accepts only biome.json and biome.jsonc and keeps the topmost on the walk from the edited file's directory to the repo root; the SessionStart probe compares separately) and apply's last bullet (a minimal config only when explicitly asked). The scaffold's .biome.json and the prompt's questions raise the dotted and walk expectations. The clone declined both entries so verify prints declined. The file_exists graders catch a config write by any tool. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [javascript-format, setup, check, read-only, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No biome.json or biome.jsonc is written and none is offered; no install, Write or Edit; the reply says the plugin is not broken: no governing config is INFO, the opt-out by design; .biome.json does not count; the topmost config on the walk governs; and a missing biome is not a FAIL while no config governs."
---

/javascript-format:setup check

This repo has a hidden .biome.json but no biome.json, and JavaScript files are never rewritten. Is the plugin broken? Why doesn't that file count? If we later add one config at the root and another in a subdirectory, which one governs a file under the subdirectory? And if biome were missing from this repo, would check call that a FAIL?
