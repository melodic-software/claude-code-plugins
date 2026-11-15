---
description: "The code-reviewer agent, given a branch that quarantines one test in a soft-fail CI step, with the spec naming the test but giving no reason, reports the quarantine as a finding"
tags: [review, code-reviewer, loosened-check]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent]
expected_outcome: "The agent's report has a finding that needs action saying the change moves 'uploads retry after a dropped connection' into a soft-fail step ('Quarantined tests' with continue-on-error in .github/workflows/ci.yml), so its failure no longer fails CI, and that the spec in review-input/issue.md names the test but gives no reason for quarantining it, which the bundled criterion 'Fail a change that loosens a check' requires"
---

Dispatch the review:code-reviewer agent on this repository's change and give it this brief: the change set is the unified diff in review-input/change.diff (base branch main, head branch checked out); the changed files are in this workspace at the paths the diff names; the spec, the issue this change resolves, is review-input/issue.md; the pull request body is review-input/pr-body.md; no shell is available in this run, so read the diff file and the files with Read, Grep and Glob instead of running git; no findings path. Do not review the change yourself. Reply with the agent's report exactly as it returned it, adding nothing.
