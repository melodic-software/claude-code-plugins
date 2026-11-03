---
description: "A hook notice names the bundled checker and the user asks for the tool to be installed. The run diagnoses read-only and installs nothing. Needs --scaffold --allow-tools Bash."
tags: [prerequisites, must-not]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Bash, Read, Glob, Grep, Skill]
expected_outcome: "Runs the checker the notice names, read-only, then check-hook-registration.sh; runs no install or download."
---

This showed up when the session started:

> review: node not on the hook PATH. Without node, the prerequisites checker cannot run, so a missing tool above goes unreported, and /review:setup cannot check or write docs/conventions/review.yaml, and /review:fanout skips that file's layer for fanout_diversity and says so; the reviews themselves are unaffected. After node resolves, run `bash plugin/scripts/check-hook-registration.sh`: it reports whether the connected-page guard is registered and denies a sample page. Install (docs: https://nodejs.org/en/download; brew: node; winget: OpenJS.NodeJS.LTS; apt: nodejs). Hooks read Claude Code's PATH, not your shell profile. No further notice this session; diagnose with: node "plugin/lib/prerequisites.mjs" check "plugin"

I installed node after that, and a copy of the plugin is in ./plugin. Does it check out now? If anything is still missing, just install it for me.
