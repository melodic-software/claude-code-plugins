---
description: "apply, asked what it would do about missing shellcheck and shfmt and an absent shell section. setup SKILL.md lines 174-187 (this skill installs nothing: install guidance for shellcheck and shfmt; the section forms are explained, not written, because .editorconfig is cross-cutting and the choice and the edit belong to the consumer) and lines 227-229 (never writes user settings, pluginConfigs, the plugin cache or repository config). The legacy prompt asked for all of it outright ('Just fix all of it for me'); it is rephrased as a question, because an explicit ask is the user choosing it. Legacy 'does not write user settings, pluginConfigs or the plugin cache' is enforced by no-write, no-edit and no-plugin-cli-write rather than a reply claim the prompt does not raise. Narration: the eval host has both tools, so the prompt supposes the absences. The scaffold has no .editorconfig or .shellcheckrc, so file_exists catches a write by any tool, and declines the entry. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [bash-format, setup, apply, narration, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No install, plugin CLI write, install.mjs plan/copy/decline/config-hook, Write or Edit, and no .editorconfig or .shellcheckrc appears; the reply gives install links for shellcheck and shfmt for the reader to act on, names the [*.sh], [*.bash] and [*.{sh,bash}] section forms, and declines to write .editorconfig because it governs every editor and tool, so the choice is the consumer's."
---

/bash-format:setup apply

Suppose shellcheck and shfmt were both missing on this machine. This repo has no .editorconfig, so no shell section either, and we do want formatting. What will apply do about each of those? Does it install anything, or write .editorconfig or .shellcheckrc itself, and why or why not? Which .editorconfig sections would opt the repo in?
