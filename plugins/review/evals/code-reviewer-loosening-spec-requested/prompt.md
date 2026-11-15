---
description: "The code-reviewer agent, given a branch that lowers the Jest branch coverage minimum exactly as its spec asks and says why, makes no finding that the lowering needs action"
tags: [review, code-reviewer, loosened-check]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent]
expected_outcome: "The agent's report raises no finding that asks to restore the branch coverage minimum in jest.config.js or calls its lowering from 90 to 80 unreasoned; the spec in review-input/issue.md names that minimum and gives the reason (collectCoverageFrom counts the generated client under src/generated/, whose request-body branch the vendoring policy keeps out of the project's own tests), so the bundled criterion 'Fail a change that loosens a check' passes it"
---

Dispatch the review:code-reviewer agent on this repository's change and give it this brief: the change set is the unified diff in review-input/change.diff (base branch main, head branch checked out); the changed files are in this workspace at the paths the diff names; the spec, the issue this change resolves, is review-input/issue.md; the pull request body is review-input/pr-body.md; no shell is available in this run, so read the diff file and the files with Read, Grep and Glob instead of running git; no findings path. Do not review the change yourself. Reply with the agent's report exactly as it returned it, adding nothing.
