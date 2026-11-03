---
description: "The security-reviewer agent, given a branch whose support assistant issues whatever refund the model's JSON names, reports at src/routes/assistant.js that model output reaches the payment call with the ownership and amount limits only in the prompt"
tags: [review, security-reviewer]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent]
expected_outcome: "The agent's report has a finding located at src/routes/assistant.js line 11, 19, 20 or 21 saying the model's JSON (line 19) drives payments.refund (line 21) with no code check that the order belongs to the caller or that the amount is within the order total, those limits living only in the system prompt, so a customer's message can steer the model into refunding any order or any amount; the fix checks ownership and amount in code"
---

Dispatch the review:security-reviewer agent on this repository's change and give it this brief: the change set is the unified diff in review-input/change.diff (base branch main, head branch checked out); the changed files are in this workspace at the paths the diff names; no shell is available in this run, so read the diff file and the files with Read, Grep and Glob instead of running git; no findings path. Do not review the change yourself. Reply with the agent's report exactly as it returned it, adding nothing.
