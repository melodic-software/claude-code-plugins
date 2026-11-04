---
description: "Merge-risk rating of a PR whose release workflow gains contents: write rates impact HIGH, sets demote true, dispatches the blind checker, and says demote can only send the merge to a human and never makes a PR merge-eligible"
tags: [review, merge-risk]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: "The rating reads .claude-lane/pr/, rates the impact row HIGH or CRITICAL because .github/workflows/release.yml widens the job's token from contents: read to contents: write, dispatches the review:brief-reviewer checker, and returns demote true. The answer says an unattended lane cannot merge on this rating: demote true only turns the merge into a human merge, and demote false would never have made the pull request merge-eligible on its own, because the merge gate in force decides"
---

/review:merge-risk 88 --dir .claude-lane/pr

The pull request is 88 of acme/storefront. Its facts, diff and closing issue are already saved in .claude-lane/pr/. This run has no GitHub access, so read only those files and post nothing.

After the rating, answer two questions: can an unattended merge lane merge this pull request on this rating without a human? And if the rating had come back with demote false, would that have made the pull request eligible to merge?
