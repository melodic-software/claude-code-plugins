---
description: "The code-reviewer agent, given a branch that adds a helper tripping the project's lint rule and removes the lint step from the required CI job in the same change with no reason given, reports at .github/workflows/ci.yml that the lint check was dropped"
tags: [review, code-reviewer]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent]
expected_outcome: "The agent's report has a finding located at .github/workflows/ci.yml line 15, 16 or 17 saying the change removes the npm run lint step from the required check job with no stated reason, so the new unused titleCase import and draft variable in src/slug.js pass CI unlinted; the fix restores the step and removes the unused code"
---

Dispatch the review:code-reviewer agent on this repository's change and give it this brief: the change set is the unified diff in review-input/change.diff (base branch main, head branch checked out); the changed files are in this workspace at the paths the diff names; no shell is available in this run, so read the diff file and the files with Read, Grep and Glob instead of running git; no findings path. Do not review the change yourself. Reply with the agent's report exactly as it returned it, adding nothing.
