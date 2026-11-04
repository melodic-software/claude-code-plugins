---
description: "check, then a teammate's machine with node and jq missing and Bash 4.4. setup SKILL.md lines 15-24 (node, jq and uname -s rows are pre-computed, so they get no tool_used grader), 54-57 (Bash below 5.0 is INFO), 58-61 (jq FAIL), 66-70 (node FAIL), 79-84 (Linux probes notify-send only), 90-96 (four toggles, unexpanded or empty is true). Narration: the host has node and jq, and a prompt that says they are broken makes the run skip the check, so it runs the check here first. Host-bound to a Linux kernel: notify-send-probe and no-osascript-probe read the Linux branch, and neither needs notify-send present. Legacy 'detects the OS family with uname -s' is dropped: the row is pre-computed at load. Legacy 'can neither classify nor emit' and 'without a notice' are narrowed to 'drops every notification': the prompt asks what happens, not why. Legacy 'EPOCHREALTIME is unset' and 'telemetry is skipped' are narrowed to 'notifications still fire' the same way. No grader says check is the only place a missing jq shows: prerequisites.json declares jq and lib/prerequisites.mjs check reports it (README lines 86-87). toggle graders pass a reply that also lists the fifth option, forward_toasts. Needs --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [desktop-notification, setup, check, read-only, narration, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "Probes notify-send and the Bash version, not osascript; a status table; missing node and jq are FAIL with the notifications consequence; Bash 4.4 is INFO with notifications still firing; a value for all four toggles, unexpanded or empty meaning true; no install, plugin CLI write, Write or Edit."
---

/desktop-notification:setup check

Run the check on this machine first. Then a hypothetical for a teammate's machine: node is missing, jq is missing and Bash is 4.4. How would check grade each of those rows, and what happens to their notifications in each case? Also, what value does check report here for each of the four toggles, and how does it read a value that shows up unexpanded or empty?
