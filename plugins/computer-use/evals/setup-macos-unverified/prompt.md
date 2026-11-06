---
description: "Legacy setup case macos-unverified-probes-are-named-not-skipped: /computer-use:setup on macOS before a 40-minute unattended run. Step 3 must not be skipped: the reply says no verified macOS probe set ships (INFO-unverified), names the three settings the operator reads in System Settings (screensaver idle delay, display sleep, require password on wake), says Claude's synthesized input still does not reset the idle timer and that this was measured on Windows, and gives no macOS probe command in the reply or through Bash (setup/SKILL.md lines 72-77 and 86-93; diagnose/reference/failure-diagnostics.md lines 96-104). names-three-settings also carries the legacy default-check expectation that the timeouts are reported as separate settings, which no Windows run can show in the Linux sandbox. Possible skill tension: the computer-use tools are absent in every run, so the verdict is blocked, and setup/SKILL.md lines 127-128 say to name the single next action when blocked, which may pull the model away from step 3 that lines 86-93 say never to omit; a smoke failure on names-three-settings may come from that. Slash-invoked (disable-model-invocation), so no Skill grader. Hard because the user asks a yes-or-no readiness question and the model knows pmset and defaults. Needs --allow-tools Bash so no-mac-probe-shell can fail."
tags: [computer-use, setup, outcome, check-only, macos, no-network]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Bash]
expected_outcome: "The reply reports the timeout step rather than omitting it: it says no verified macOS probes ship (unverified), names the screensaver idle delay, display sleep and the password or lock on wake as the settings to read in System Settings, says Claude's synthesized input does not reset the idle timer, and says that behavior was measured on Windows. It gives no macOS probe command (pmset, ioreg, osascript, caffeinate, or defaults read or write) as code or as an instruction, and no Bash command runs one."
---

/computer-use:setup

I'm on macOS 15, using computer use in the Claude Code CLI. Is computer use ready for a 40-minute unattended run?
