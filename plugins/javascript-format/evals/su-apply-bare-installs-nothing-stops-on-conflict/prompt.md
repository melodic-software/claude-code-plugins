---
description: "Bare apply in a repository with no Biome config and a package-lock.json that contradicts the package.json packageManager field, asked what it would do. setup SKILL.md lines 36-38 and 142-144 (bare apply installs nothing; apply install-biome is the explicit argument), 148-150 (a lockfile that contradicts packageManager stops with manager-specific guidance; never a competing lockfile), 162-163 (never installs system packages), 184-185 and 199 (never writes user settings, pluginConfigs or the plugin cache) and 190-191 (a minimal biome.json only when explicitly asked; the plugin imposes no rules of its own). The legacy prompt asked for an install and a config outright; it is rephrased as a question, because an explicit ask is the user choosing it, and lines 190-191 allow a config on such an ask. The scaffold has no config, so the file_exists graders catch a write by any tool, and a new lockfile or local biome catches an install by any manager, bun included. A host with biome on PATH may report the binary as resolved, against the prompt's premise; the questions still ask what apply and apply install-biome would do. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [javascript-format, setup, apply, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No install, install.mjs write verb, claude plugin write, Write or Edit, and no Biome config, new lockfile or local biome appears; the reply says bare apply installs nothing and apply install-biome is the authorizing argument, that here it would stop with manager-specific guidance because the lockfile contradicts packageManager, that biome.json is written only on an explicit ask, and that the skill never installs system packages or writes Claude Code settings."
---

/javascript-format:setup apply

Biome isn't installed and this repo has no biome.json. What will apply do about each of those? This repo's package-lock.json and its packageManager field disagree: what would `apply install-biome` do here? Would this skill ever install system packages such as jq, or change my Claude Code settings?
