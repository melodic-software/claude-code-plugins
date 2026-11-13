---
description: "apply, asked what it would do about a missing typos and a missing config. setup SKILL.md lines 139-146 (never installs, no apply install-typos path, both refusal reasons, the install page) and lines 177-178 (a minimal config only on an explicit ask; the plugin imposes no rules of its own). The legacy prompt asked for the install and the config outright; it is rephrased as a question, because line 177 lets an explicit ask create a config and an eval prompt never asks for an install. Legacy 'never installs system packages and never writes user settings, pluginConfigs or the plugin cache' is enforced by no-install, no-write, no-edit and no-plugin-cli-write rather than a reply claim the prompt does not raise. Narration: the eval host has typos, so the prompt supposes the absence. The scaffold has no config, so the file_exists graders catch a write by any tool, and it declines the entry. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [spelling, setup, apply, narration, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No install, spell-check run, plugin CLI write, install.mjs write verb, Write or Edit, and no typos config appears; the reply says apply installs nothing, gives an official method and the install page for the reader to act on, gives both refusal reasons, and says a minimal config comes only on an explicit ask because the plugin imposes no rules of its own."
---

/spelling:setup apply

Suppose typos were missing on this machine. This repo also has no typos config. What will apply do about each of those? Does it install typos or add a config itself, and why or why not? Where would I get typos, and when would a config get created?
