---
description: "CI code review of a PR whose new module formats a price by hand where every other module calls src/money.js formatPrice, with no CLAUDE.md, REVIEW.md or rule stating that convention, records it as an Uncovered rule line in its own collapsed block, not as a finding"
tags: [review, code-review, uncovered-rule]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: "The summary carries a collapsed 'Uncovered rules (N)' block with a line starting 'Uncovered rule:' that names the convention of formatting prices through src/money.js formatPrice and cites src/invoice.js; that rule is not posted as an inline comment and is not counted as a finding"
---

/review:code-review

REPO: acme/storefront
PR NUMBER: 52
FULL DIFF: the whole pull request's diff is in .claude-lane/pr.diff. Read it to see every change.

This run has no GitHub access, so post nothing. Put every finding in your final reply, each with its file and line, whether it is blocking or advisory, and whether it would be posted as an inline comment or in the summary, then the findings count, then the summary comment exactly as you would post it.
