---
description: "The code-reviewer agent, given a branch that sets the required lint step to soft-fail as its spec asks and with the spec's reason, still reports the soft-fail as a finding, since only a quarantined flaky test may soft-fail"
tags: [review, code-reviewer, loosened-check]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent]
expected_outcome: "The agent's report has a finding that needs action at .github/workflows/ci.yml saying the change sets the lint step to soft-fail (continue-on-error: true), so lint failures no longer fail the job, and that the spec's reason does not allow it because the bundled criterion 'Fail a change that loosens a check' passes a soft-fail only as the quarantine of a flaky test"
---

Dispatch the review:code-reviewer agent on this repository's change and give it this brief: the change set is the unified diff in review-input/change.diff (base branch main, head branch checked out); the changed files are in this workspace at the paths the diff names; the spec, the issue this change resolves, is review-input/issue.md; the pull request body is review-input/pr-body.md; no shell is available in this run, so read the diff file and the files with Read, Grep and Glob instead of running git; no findings path. Do not review the change yourself. Reply with the agent's report exactly as it returned it, adding nothing.
