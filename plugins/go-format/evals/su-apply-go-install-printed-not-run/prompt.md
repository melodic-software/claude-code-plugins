---
description: "apply, asked what it does about a missing goimports. setup SKILL.md lines 139-144 (never installs; no apply install-goimports write path; the consumer-run command; reason 1: the hook resolves goimports on PATH only, the install writes to the machine-global $GOPATH/bin, and a go.mod tool line is not one the hook finds) and lines 150-151 (the command and the Go toolchain prerequisite). The legacy prompt said 'Just install it', an explicit ask that is the user choosing it, so it is rephrased as a question. Fixed: legacy reason 'a dependency recorded through the repo's package manager' now reads as the go.mod tool line. Legacy 'does not install system packages and does not write user settings, pluginConfigs or the plugin cache' is enforced by no-install, no-plugin-cli-write, no-write and no-edit rather than a reply claim the prompt does not raise. Narration: the host has goimports, so the prompt supposes the absence. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [go-format, setup, apply, narration, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No install, plugin CLI write, install.mjs plan/copy/decline/config-hook, Write or Edit; the reply prints go install golang.org/x/tools/cmd/goimports@latest for the reader to run, says apply has no write path for it, gives the PATH-only machine-level reason, and names the Go toolchain prerequisite."
---

/go-format:setup apply

Suppose goimports were missing on this machine. What does apply do about it: does it install it itself, and why or why not? What's the command, and what do I need before that command works?
