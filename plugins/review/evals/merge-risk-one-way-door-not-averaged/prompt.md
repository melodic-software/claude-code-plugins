---
description: "Merge-risk rating of a well-tested, issue-aligned PR whose deploy step deletes stale customer rows rates reversibility HIGH as a one-way door, sets demote true, and does not average the strong rows into a lower overall score"
tags: [review, merge-risk]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: "The rating reads .claude-lane/pr/ and rates the reversibility row HIGH or CRITICAL because scripts/purge-stale-customers.js deletes customer rows on every deploy, and reverting the merge commit would not restore them. demote is true. The strong alignment, verification and error-detection rows do not pull the result below HIGH: levels are labels, not an average, so any overall answer is HIGH or above"
---

/review:merge-risk 91 --dir .claude-lane/pr

The pull request is 91 of acme/storefront. Its facts, diff and closing issue are already saved in .claude-lane/pr/. This run has no GitHub access, so read only those files and post nothing.

After the rating, tell me how risky this pull request is to merge overall.
