---
description: "check, then a teammate's machine with the hook off, node broken and jq missing. setup SKILL.md lines 51-55 (disabled: every absence but Node.js downgrades to INFO; re-enabling restores FAIL) and step 1 (lines 57-62: probe with node --version, a stale shim resolves yet cannot run, FAIL in every toggle state, install or repair). Narration: the host has working node and jq, and a prompt that says node is broken makes the run skip the probe, so it asks for the probe here first. The scaffold opts in with a root config, so re-enabling does restore jq's FAIL (lines 65-66), and declines the entry. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [markdown-format, setup, check, read-only, narration, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "Runs node --version; says Node.js is FAIL despite the disabled toggle with an install-or-repair remediation, a missing jq is INFO while the hook is off and FAIL again once re-enabled, and resolving on PATH is not enough. No install, lint run, write or edit."
---

/markdown-format:setup check

Run the check on this machine first, including the Node.js probe. Then a hypothetical for a teammate's machine in the same repo: they turned the hook off (markdown_format_enabled=false), node is broken and jq is missing. How would check grade the Node.js row and the jq row there, and what is the remediation for Node.js? Would node resolving on their PATH be enough for a PASS? What changes for the jq row if they turn the hook back on?
