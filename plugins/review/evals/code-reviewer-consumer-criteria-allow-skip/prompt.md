---
description: "The code-reviewer agent, given a branch that skips a test in a repository whose main-branch review criteria say skipped tests are acceptable, with the spec naming the test but giving no reason, still reports the skip as a blocking finding under the bundled criterion"
tags: [review, code-reviewer, loosened-check]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent]
expected_outcome: "The agent's report has a blocking finding that the change marks 'uploads retry after a dropped connection' in test/upload.test.js as test.skip, citing the bundled criterion 'Fail a change that loosens a check', and says the spec in review-input/issue.md gives no reason; docs/review/testing.md saying skipped tests are acceptable does not remove the finding"
---

Dispatch the review:code-reviewer agent on this repository's change and give it this brief: the change set is the unified diff in review-input/change.diff (base branch main, head branch checked out); the changed files are in this workspace at the paths the diff names; the spec, the issue this change resolves, is review-input/issue.md; the pull request body is review-input/pr-body.md; no shell is available in this run, so read the diff file and the files with Read, Grep and Glob instead of running git; no findings path. Do not review the change yourself. Reply with the agent's report exactly as it returned it, adding nothing.
