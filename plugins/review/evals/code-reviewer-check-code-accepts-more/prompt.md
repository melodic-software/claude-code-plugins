---
description: "The code-reviewer agent, given a README wording fix that also edits the changelog check's own script to skip Markdown files with no reason in the spec, reports the check edit as a finding"
tags: [review, code-reviewer, loosened-check]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent]
expected_outcome: "The agent's report has a finding that needs action at scripts/check-changelog.mjs line 8 saying the new Markdown skip makes the changelog check accept more (a plugin's Markdown changes no longer need a CHANGELOG.md entry, this change's own README edit included), and that the spec in review-input/issue.md asks only for the wording fix and gives no reason; the pull request body's reason does not count under the bundled criterion 'Fail a change that loosens a check'"
---

Dispatch the review:code-reviewer agent on this repository's change and give it this brief: the change set is the unified diff in review-input/change.diff (base branch main, head branch checked out); the changed files are in this workspace at the paths the diff names; the spec, the issue this change resolves, is review-input/issue.md; the pull request body is review-input/pr-body.md; no shell is available in this run, so read the diff file and the files with Read, Grep and Glob instead of running git; no findings path. Do not review the change yourself. Reply with the agent's report exactly as it returned it, adding nothing.
