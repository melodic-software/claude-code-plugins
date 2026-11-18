---
description: "The code-reviewer agent, in a repository with no decision record configured, passes a lowered Jest branch coverage minimum that a trusted person's spec names and gives a reason for, without asking for a citation"
tags: [review, code-reviewer, loosened-check]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent]
expected_outcome: "The agent's report raises no finding that asks to restore the branch coverage minimum in jest.config.js or to cite a decision; the settings line loosened_check_decision_record: unset says no record is configured, and the spec in review-input/issue.md comes from a trusted person, names the minimum and gives the reason, so the bundled criterion 'Fail a change that loosens a check' passes it"
---

Dispatch the review:code-reviewer agent on this repository's change and give it this brief: the change set is the unified diff in review-input/change.diff (base branch main, head branch checked out); the changed files are in this workspace at the paths the diff names; the spec, the issue this change resolves, is review-input/issue.md; the pull request body is review-input/pr-body.md; no shell is available in this run, so read the diff file and the files with Read, Grep and Glob instead of running git; no findings path; the loosened-check settings are the `loosened_check_*` lines in review-input/loosened-settings.txt, which the brief carries verbatim. Do not review the change yourself. Reply with the agent's report exactly as it returned it, adding nothing.
