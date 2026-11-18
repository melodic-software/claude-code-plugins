---
description: "The code-reviewer agent, given a branch that lowers the Jest branch coverage minimum exactly as a trusted person's spec asks and says why, flags the lowering because the spec does not cite the owner's decision"
tags: [review, code-reviewer, loosened-check]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent]
expected_outcome: "The agent's report flags the lowering of the branch coverage minimum in jest.config.js from 90 to 80 as a finding under the bundled criterion 'Fail a change that loosens a check'; the spec in review-input/issue.md comes from a trusted person, names the minimum and gives a reason, but holds no line link to the owner's decision and no verbatim words, so the spec gives no reason"
---

Dispatch the review:code-reviewer agent on this repository's change and give it this brief: the change set is the unified diff in review-input/change.diff (base branch main, head branch checked out); the changed files are in this workspace at the paths the diff names; the spec, the issue this change resolves, is review-input/issue.md; the pull request body is review-input/pr-body.md; no shell is available in this run, so read the diff file and the files with Read, Grep and Glob instead of running git; no findings path; the loosened-check settings are the `loosened_check_*` lines in review-input/loosened-settings.txt, which the brief carries verbatim. Do not review the change yourself. Reply with the agent's report exactly as it returned it, adding nothing.
