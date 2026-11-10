---
description: 'An audit runs the decomposed-parent close over two parents split with no spec container, every child closed as completed. #300''s Finish line reads merged, so it closes as completed after the dependents step, with a comment listing its children and their PRs. #400''s Finish line reads in use, which the tracker cannot show, so it stays open and gets one marked comment quoting the Finish line and naming the support lead as its checker. closes-300 and names-400-checker read the reply, no-close-400 keeps #400 open. Read-only tools, graded on the reply.'
tags: [track, audit, decompose]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The audit finds no stale claim, orphan or label defect, then finds parents #300 and #400 through their children''s Refs lines. It runs "Dependents on close" for #300 and closes it as completed with a comment listing #301, #302 and #303 and PRs #311, #312 and #313. It leaves #400 open and posts one comment, marked <!-- work-items:parent-close outcome=open -->, that quotes the in use Finish line and names the support lead as the checker who closes it. The report lists both parents with their results.'
---

/work-items:track audit

The repository is on GitHub. No item is assigned, the repository has no recurring schedule, and every open item has an Issue Type and no conflicting labels.

Two open issues were split by /work-items:decompose into plain issues with no spec container; neither carries the container label. Each child's body opens with a `## Parent` section reading `Refs #<parent>` and ends with `<!-- work-items:born-triaged -->`. Every child was opened by the login this session's item writes post as, the account decompose published them from.

- #300 "Export refunds for reconciliation". Its Goal has `- Finish line: merged — checked by ci-status via the pull request's checks`. Children #301, #302 and #303 are closed as completed, by merged PRs #311, #312 and #313. No open item is blocked by #300.
- #400 "Ward rota in the scheduling app". Its Goal has `- Finish line: in use — checked by the support lead via the weekly ticket report`. Children #401 and #402 are closed as completed, by merged PRs #411 and #412. No open item is blocked by #400.

No comment on either parent carries a `work-items:parent-close` marker yet.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
