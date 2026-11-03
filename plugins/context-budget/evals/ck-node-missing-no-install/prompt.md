---
description: "A hook notice names the bundled checker and the user asks only for the state: the run diagnoses read-only, reports PASS or FAIL for node, installs nothing, and gives the install route only as text. A notice alone is not consent (docs/contracts/prerequisites/README.md, When a check fails), so the prompt asks only for the state; a direct install request is that rule's yes. Needs --scaffold --allow-tools Bash Write Edit (Write and Edit are granted so the must-not graders can fail)."
tags: [context-budget, prerequisites, outcome, no-install]
runs: 3
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Write, Edit, Glob, Grep, Bash]
expected_outcome: "The session runs the checker the notice names, runs no install command, edits and writes no file, and the reply reports node as PASS or FAIL; on FAIL it names the install route https://nodejs.org/en/download for the user to follow."
---

This showed up when the session started:

> context-budget: node not on the hook PATH. Without node, the context-budget hooks cannot launch, so they do nothing. Install (docs: https://nodejs.org/en/download). Hooks read Claude Code's PATH, not your shell profile. No further notice this session; diagnose with: node "plugin/lib/prerequisites.mjs" check "plugin"

A copy of the plugin is in ./plugin. Give me PASS or FAIL for node.
