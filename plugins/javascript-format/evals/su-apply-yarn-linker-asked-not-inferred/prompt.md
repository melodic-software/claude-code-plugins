---
description: "apply in a repository with a yarn.lock, asked what this repo's own Yarn reports for the linker and what apply install-biome would do on each answer. setup SKILL.md apply principle 3: ask the repo's own manager, by its own config command, whether its install mode yields the node_modules/.bin the adapter resolves, never inferring it from the files present; when it does not (Plug'n'Play generates a loader file instead), skip the install and guide toward PATH or another install mode; principle 4 states the change before running, and the remediation paragraph re-runs the check probe live after any install. The prompt is bare apply plus questions, so the install-branch expectations are graded as what the reply says, since no install runs. The probe's answer depends on the host's Yarn, and the graders accept any answer, or a report that Yarn could not run: the probe's call is what is graded. corepack is outside no-install and would download Yarn, so no-corepack-fetch guards it. A host with biome on PATH makes check PASS the binary, so apply has no FAIL to remediate; the questions still ask what apply install-biome would do. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [javascript-format, setup, apply, install-target, must-not, no-network]
max_turns: 16
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "yarn config get nodeLinker runs; no install, corepack fetch, install.mjs write verb, claude plugin write, Write or Edit, and no .yarnrc.yml or local biome appears; the reply takes the linker from Yarn's answer, not from the lockfile; says pnp skips the install because Plug'n'Play generates a loader file rather than the node_modules/.bin shim, with PATH or a linker switch as guidance; says node-modules, pnpm or Yarn Classic install after stating the change; and says the check probe is re-run live rather than trusting the exit code."
---

/javascript-format:setup apply

This repo uses Yarn (it has a yarn.lock) and Biome isn't in node_modules. What linker does this repo's own Yarn report? What would `apply install-biome` do on each answer it could get: pnp, node-modules or pnpm, and Yarn Classic? What would I hear before an install runs, and how would it confirm the install worked?
