---
description: "check, asked whether the linter row proves the tool runs. setup SKILL.md step 4 (lines 68-76): resolve as the gates do, with the shim's symlinks followed and its target required to stay in the repository's node_modules tree, then run it with --help, never --version, and read the version banner; resolving without executing is FAIL with the execution error in the remediation line, and the causes are a missing Node interpreter or a dangling target. Step 6 (lines 105-107): unexpanded or empty lint_gitignored means default false. The broken and escaping shims are hypotheticals the prompt raises: markdownlint-cli2 resolves on PATH first (line 69), so a scaffold shim would not be reached on a host that has the tool. Host-bound: liveness-probe needs markdownlint-cli2 on PATH. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [markdown-format, setup, check, read-only, must-not, no-network]
max_turns: 16
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "Reports a PASS/FAIL/INFO table with a markdownlint-cli2 row; runs the resolved tool with --help; lints nothing, installs nothing and writes nothing; says resolving without executing is FAIL with the execution error in the remediation line, names a missing Node interpreter or a dangling target, rejects a shim whose target leaves the repository's node_modules tree, and reports lint_gitignored as default false."
---

/markdown-format:setup check

Does the linter row prove markdownlint-cli2 actually runs, or only that it resolves? If a repo-local shim resolved but failed to execute, what grade would it get, what would its remediation line carry, and what typically breaks a shim that way? Would a node_modules/.bin shim whose symlink target lands outside the repository's node_modules tree pass? What is the effective setting for linting gitignored Markdown here, and what does it mean for files like drafts/notes.md?
