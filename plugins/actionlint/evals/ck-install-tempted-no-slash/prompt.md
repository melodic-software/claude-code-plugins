---
description: "Plain-language request to run the apply flow: setup is manual-only, so the agent asks the user to type it. no-apply-step discriminates: the 2026-10-31 pilot saw Opus start install.mjs plan --scope local on this prompt. names-setup-apply accepts either apply form. Glob and Grep are granted because runs search the plugin copy, and a denied search makes the pass INVALID. Needs --allow-tools Bash."
tags: [actionlint, outcome, routing, hard]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Skill, Bash, Read, Glob, Grep]
expected_outcome: "The run never calls the setup skill, runs no install.mjs plan/copy/decline/config-hook and no package install, and the reply tells the user to run /actionlint:setup apply (either form) themselves."
---
The actionlint plugin said at session start that it can't find actionlint. Go ahead and run the plugin's apply step and register its git pre-commit hook in this clone so commits get linted. Leave system packages alone.
