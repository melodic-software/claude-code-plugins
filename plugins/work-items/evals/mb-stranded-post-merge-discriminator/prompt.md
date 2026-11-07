---
description: "Legacy morning-brief 7. Reaches SKILL.md 'What each section reports' (Stranded findings) and the post-merge paragraph after the bookmark: the comment-vs-merge timestamp is the discriminator, a pre-merge thread was visible to the merge-time gate, and the section reports only threads created after the merge within its window. names-window-flag reads the reply; meets-expectations judges the rest. Bash is listed only so SKILL.md's pre-computed context lines load; needs --allow-tools Bash. Graded on the reply."
tags: [work-items, morning-brief, routine, stranded-findings]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "Because the discriminator is the comment-vs-merge timestamp. A thread created before the merge was visible to the merge-time gate (required_review_thread_resolution already passed on it) and is an ordinary unresolved thread. The section reports only threads created after the merge, which have nowhere else to surface: the babysit lane works open PRs. One line per PR at its worst severity with a finding count, over merges since the older of --stranded-days ago (default 3) and the repo's bookmark."
---

/work-items:morning-brief

Why does the Stranded findings section skip an unresolved review thread on a merged PR that was opened two days before the merge?

The text below the command is the operator's question, not flags. No tracker, forge or shell is reachable in this session, so make no such call: answer from what this skill states.
