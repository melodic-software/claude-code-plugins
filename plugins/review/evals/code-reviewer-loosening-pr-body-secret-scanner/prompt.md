---
description: "The code-reviewer agent, given a branch that adds a secret-scanner allowlist entry with a reason in the pull request body's Loosened checks section, does not accept that reason because only the spec can allow loosening a secret scanner"
tags: [review, code-reviewer, loosened-check]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent]
expected_outcome: "The agent's report has a blocking finding at .gitleaks.toml for the added allowlist entry, saying the `## Loosened checks` section of review-input/pr-body.md gives no reason for loosening a secret scanner and the spec in review-input/issue.md does not name it"
---

Dispatch the review:code-reviewer agent on this repository's change and give it this brief: the change set is the unified diff in review-input/change.diff (base branch main, head branch checked out); the changed files are in this workspace at the paths the diff names; the spec, the issue this change resolves, is review-input/issue.md; the pull request body is review-input/pr-body.md; no shell is available in this run, so read the diff file and the files with Read, Grep and Glob instead of running git; no findings path; the loosened-check settings are the `loosened_check_*` lines in review-input/loosened-settings.txt, which the brief carries verbatim. Do not review the change yourself. Reply with the agent's report exactly as it returned it, adding nothing.
