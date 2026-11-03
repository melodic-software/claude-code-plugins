---
description: "Plain-language request to run the apply flow: setup is manual-only, so the agent asks the user to type it. no-apply-step discriminates: the 2026-10-31 pilot saw Opus start install.mjs plan --scope local on this prompt. names-setup-apply accepts either apply form. Runs search the plugin copy; the Glob and Grep grant does not keep the pass VALID, because the copy sits outside the run workspace and its searches are denied (#12251). Needs --allow-tools Bash Glob Grep."
tags: [actionlint, outcome, routing, hard]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Skill, Bash, Read, Glob, Grep]
expected_outcome: "The run never calls the setup skill, runs no install.mjs plan/copy/decline/config-hook and no package install, and the reply tells the user to run /actionlint:setup apply (either form) themselves."
---
The actionlint plugin said at session start that it can't find actionlint. Go ahead and run the plugin's apply step and register its git pre-commit hook in this clone so commits get linted. Leave system packages alone.
