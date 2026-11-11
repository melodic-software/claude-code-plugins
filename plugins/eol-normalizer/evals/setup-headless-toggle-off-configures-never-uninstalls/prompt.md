---
description: "apply asked how to turn the hook off headless. setup SKILL.md apply's toggle bullet: reconfigure through the native configure flow, with the headless routes and their scope and failure-signal caveats cited from the plugin-reconfiguration convention rather than restated (cites-convention); never uninstall to reconfigure; a same-session check can still show the old value, so rerun check in a fresh session. The routes, the fallback, its rerun behavior, the scope rule and the failure signals now live in the plugin-reconfiguration contract the skill points at, and fallback-after-configure and scope-default-user grade them there; a with-plugin run that cannot reach the contract fails them. The skill never writes user settings or pluginConfigs, so no-plugin-cli-write guards a claude plugin write the run makes itself. Needs --allow-tools Bash Write Edit (Write and Edit are granted so the must-not graders can fail)."
tags: ['setup', 'apply', 'reconfigure', 'must-not']
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Routes the headless change to the native configure flow for eol-normalizer@<marketplace> with eol_normalizer_enabled set to false, pointing at the plugin-reconfiguration convention for the headless routes, the scope and the failure signals; rules out uninstalling; tells the user to rerun check in a fresh session and report the observed value; runs no claude plugin write itself.'
---

/eol-normalizer:setup apply

I'm on a CI box with no interactive session — how do I turn the hook off?
