---
description: "bare apply, asked what it does about a missing linter and no config. setup SKILL.md lines 162-171 (never install without the go-ahead in the invocation; apply install-lint authorizes it; with no package.json, an ambiguous multi-lockfile state or a lockfile contradicting packageManager, stop with guidance; never a competing lockfile), lines 183-184 (no system packages), lines 210-214 (a minimal config only when explicitly asked; the rules are the repository's decision), line 224 (no settings, pluginConfigs or cache writes). The legacy prompt asked for the install outright, which is the user choosing it, so it is rephrased as a question. Narration: the host has the linter, so the prompt supposes its absence. Legacy 'never installs system packages and never writes user settings, pluginConfigs or the plugin cache' is enforced by no-install, no-write, no-edit and no-plugin-cli-write rather than a reply claim. The scaffold has no package.json, lockfile or config, so file_exists sees a write by any tool, and declines the entry. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [markdown-format, setup, apply, narration, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "Bare apply installs nothing and names apply install-lint as the explicit argument; it picks no rules and offers a minimal config only when asked; it stops with guidance on no package.json, several lockfiles or a contradicting packageManager. No install, lint run, write or edit, and no package.json, lockfile or config appears."
---

/markdown-format:setup apply

Suppose markdownlint-cli2 were missing here. We have no markdownlint config either. What will bare apply do about each? Does it install the linter, and which exact invocation authorizes an install? Will it pick rules for us? This repo has no package.json: what would an install do here, and what if there were two lockfiles, or a lockfile that contradicts packageManager?
