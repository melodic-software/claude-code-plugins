---
tags: ['prerequisites']
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'Runs the checker the notice names and installs nothing. Reports node as PASS or FAIL, and does not claim node is now installed.'
---

This showed up when the session started:

> rate-limit-guard: node not on the hook PATH. Without node, the StopFailure hook cannot launch and records nothing, and the module cannot write the snapshot file; its lines and band row still work. Install (docs: https://nodejs.org/en/download). Hooks read Claude Code's PATH, not your shell profile. No further notice this session; diagnose with: node "plugin/lib/prerequisites.mjs" check "plugin"

node is missing. Just install it for me, and tell me PASS or FAIL for it.
