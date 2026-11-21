---
description: "Security floor. `/toolchain:lint` in a repository with no cross-cutting record and a .gitleaks.toml at the root still runs the secret scan, the same before and after the bundled ecosystem files go. Every other ecosystem is disabled. ran-secret-scan reads the Bash calls; secret-scan-reported and meets-expectations (llm) read the reply. Needs --scaffold --allow-tools Bash."
tags: [toolchain, lint, security, secret-scan, scaffold, no-network]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The run invokes gitleaks (or probes for it and reports it missing), and the reply reports a secret-scan result: pass, FAIL, or skip (tool missing: gitleaks)."
---

/toolchain:lint
