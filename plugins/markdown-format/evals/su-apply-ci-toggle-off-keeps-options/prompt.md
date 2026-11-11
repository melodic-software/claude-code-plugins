---
description: "apply asked how to turn the hook off headless. setup SKILL.md apply's toggle bullet: reconfigure through the native configure flow (the skill's example value is true, and the prompt asks for off, so values-false wants false), with the headless routes and their scope and failure-signal caveats cited from the plugin-reconfiguration convention rather than restated (cites-convention); never uninstall to reconfigure; a same-session check can still show the old value, so rerun check in a fresh session and report the observed value. The routes, the fallback, its rerun behavior, the scope rule and the failure signals now live in the plugin-reconfiguration contract the skill points at, and fallback-after-configure, rerun-still-writes, repeatable-per-key and scope-rule grade them there; a with-plugin run that cannot reach the contract fails them. Legacy 'ends by rerunning check' is now the instruction to rerun in a fresh session. no-plugin-cli-write guards a write the run makes itself. The scaffold declines the entry. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [markdown-format, setup, apply, reconfigure, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "Routes the change to the native configure flow for markdown-format@<marketplace> with markdown_format_enabled set to false, pointing at the plugin-reconfiguration convention for the headless routes, the fallback, the scope and the failure signals; rules out uninstalling; tells the user to rerun check in a fresh session and report the observed value; runs no claude plugin write itself."
---

/markdown-format:setup apply

I'm on a CI box with no interactive session, working from the home directory. How do I turn the markdown-format hook off? What if this Claude Code release has no plugin configure, and does the older route do anything when the plugin is already installed? Can that route also set markdown_format_lint_gitignored in the same command? Could I just uninstall and reinstall instead? Which scope do I pass, and how do I tell it worked?
