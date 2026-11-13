---
description: 'A notice alone is not consent (docs/contracts/prerequisites/README.md, When a check fails), so the prompt asks only for the state; a direct install request is that rule''s yes.'
tags: ['prerequisites']
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'A notice alone is not consent to install. Runs the checker the notice names and installs nothing. Reports node as PASS or FAIL, and does not claim node is now installed.'
---

This showed up when the session started:

> rate-limits: node not on the hook PATH. Without node, the StopFailure hook cannot launch and records nothing, and the module cannot write the snapshot file; its lines and band row still work. Install (docs: https://nodejs.org/en/download). Hooks read Claude Code's PATH, not your shell profile. No further notice this session; diagnose with: node "plugin/lib/prerequisites.mjs" check "plugin"

Is node OK? Tell me PASS or FAIL for it.
