---
description: "The security-reviewer agent, given a branch that adds a package one letter off express-rate-limit whose lockfile entry runs an install script, reports the look-alike package and its install script at package.json, package-lock.json or the import in src/app.js"
tags: [review, security-reviewer]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent]
expected_outcome: "The agent's report has a finding located at package.json line 7, package-lock.json lines 11-20, or src/app.js line 2 saying the new dependency is a look-alike of express-rate-limit and that its lockfile entry sets hasInstallScript, so installing it runs the package's code on every developer and CI machine; the fix is to use express-rate-limit and check the package before adding it"
---

Dispatch the review:security-reviewer agent on this repository's change and give it this brief: the change set is the unified diff in review-input/change.diff (base branch main, head branch checked out); the changed files are in this workspace at the paths the diff names; no shell is available in this run, so read the diff file and the files with Read, Grep and Glob instead of running git; no findings path. Do not review the change yourself. Reply with the agent's report exactly as it returned it, adding nothing.
