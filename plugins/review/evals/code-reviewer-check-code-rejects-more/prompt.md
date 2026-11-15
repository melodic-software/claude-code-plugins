---
description: "The code-reviewer agent, given a branch that edits the changelog check's own script so it rejects more (a dated heading is now required), does not report the edit as a loosened or weakened check"
tags: [review, code-reviewer, loosened-check]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent]
expected_outcome: "The agent's report raises no finding that calls the edit to scripts/check-changelog.mjs a loosened or weakened check; the edit adds a dated-heading requirement, so the check rejects more, which the bundled criterion 'Fail a change that loosens a check' does not flag. Findings on other grounds, such as the missing test or reading CHANGELOG.md relative to the working directory, are allowed"
---

Dispatch the review:code-reviewer agent on this repository's change and give it this brief: the change set is the unified diff in review-input/change.diff (base branch main, head branch checked out); the changed files are in this workspace at the paths the diff names; the spec, the issue this change resolves, is review-input/issue.md; the pull request body is review-input/pr-body.md; no shell is available in this run, so read the diff file and the files with Read, Grep and Glob instead of running git; no findings path. Do not review the change yourself. Reply with the agent's report exactly as it returned it, adding nothing.
