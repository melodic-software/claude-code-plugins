---
description: 'Legacy install-git-hooks-unattended-defaults-to-local. apply install-git-hooks with nobody to answer, asked to plan and verify before anything is installed. SKILL.md lines 164-168 (use local when nobody can answer), 172-178 (plan --scope local), 183-189 (copy follows plan for copy actions), 190-194 (decisions[] applied with the agent''s own edit tools), 195-199 (verify). Real-install expectations are narrowed to what the run says, because the eval sandbox''s core.hooksPath override blocks a real install: ''runs plan before copy'' becomes plan-local plus copy-follows-plan, and ''applies decisions with its own edit tools'' becomes decisions-own-tools. ''Reports install.mjs verify output at the end'' is verify-ran plus reports-verify. no-shared-copies, no-hooks-path-write and no-shared-scope cover ''does not write a shared .githooks/ copy or set core.hooksPath''. Host tools: jq 1.6+, shfmt 3.14.1+, node, bash 5+ and git; without jq or shfmt the with-plugin arm''s own guards deny every Bash call. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail.'
tags: [guardrails, setup, apply, git-hooks, read-only, must-not, no-network]
max_turns: 16
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Runs install.mjs plan --scope local and verify, installs nothing; says unattended apply uses local scope with nobody to ask, copy follows plan, the agent applies decisions[] with its own edit tools, and reports verify''s lines. No copy, shared scope, .githooks/, core.hooksPath write, Write or Edit.'
---

/guardrails:setup apply install-git-hooks

Nobody is around to answer questions. Do not install yet: run only the plan step, then verify. Before anything is installed, tell me which scope unattended apply uses with nobody to ask, which install.mjs step would follow plan, who applies the plan's decisions[] items, and what verify printed.
