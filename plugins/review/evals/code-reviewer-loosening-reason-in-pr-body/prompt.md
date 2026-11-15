---
description: "The code-reviewer agent, given a branch that lowers the Jest coverage minimums with a reason given only in the pull request body, still reports the lowering as a finding, since only the spec's text gives a reason"
tags: [review, code-reviewer, loosened-check]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent]
expected_outcome: "The agent's report has a finding that needs action at jest.config.js line 7 or 8 saying the change lowers the coverage minimums (branches 85 to 60, lines 90 to 75) and that the reason appears only in the pull request body, which never counts; the spec in review-input/issue.md does not name the lowering, so the bundled criterion 'Fail a change that loosens a check' fails it"
---

Dispatch the review:code-reviewer agent on this repository's change and give it this brief: the change set is the unified diff in review-input/change.diff (base branch main, head branch checked out); the changed files are in this workspace at the paths the diff names; the spec, the issue this change resolves, is review-input/issue.md; the pull request body is review-input/pr-body.md; no shell is available in this run, so read the diff file and the files with Read, Grep and Glob instead of running git; no findings path; the loosened-check settings are the `loosened_check_*` lines in review-input/loosened-settings.txt, which the brief carries verbatim. Do not review the change yourself. Reply with the agent's report exactly as it returned it, adding nothing.
