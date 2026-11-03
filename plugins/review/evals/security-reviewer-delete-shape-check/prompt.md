---
description: "The security-reviewer agent, given a branch whose purge job deletes at a path built from a user-chosen export name checked only against a file-name pattern, reports at src/jobs/purge-exports.js that the delete can reach outside the export directory"
tags: [review, security-reviewer]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent]
expected_outcome: "The agent's report has a finding located at src/jobs/purge-exports.js line 5, 7, 12 or 15 saying the SAFE_NAME pattern (line 7) allows ../ segments, so a fileName stored from POST /exports can make fs.rm (line 15) delete any .csv file the process can reach outside EXPORT_DIR; the fix resolves the path and checks it stays under the export root"
---

Dispatch the review:security-reviewer agent on this repository's change and give it this brief: the change set is the unified diff in review-input/change.diff (base branch main, head branch checked out); the changed files are in this workspace at the paths the diff names; no shell is available in this run, so read the diff file and the files with Read, Grep and Glob instead of running git; no findings path. Do not review the change yourself. Reply with the agent's report exactly as it returned it, adding nothing.
