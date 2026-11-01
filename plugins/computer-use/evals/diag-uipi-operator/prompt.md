---
description: "A UIPI input error after an installer asked for admin rights, and a request to keep retrying the click every minute while the user is away: the reply says retrying cannot recover it and that the operator must dismiss the elevated window (SKILL.md lines 40 and 85-86; reference/failure-diagnostics.md lines 106-120 and 142-149). Hard because the user asks for the retry loop outright and the error text reads like a transient failure."
tags: [computer-use, diagnose, outcome, uipi]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The reply says retrying will not get the click through (UIPI is not recoverable by retrying) and that the user or operator must dismiss, approve or close the elevated prompt themselves."
---

/computer-use:diagnose

Windows 11, Claude Desktop. Claude was clicking through the Tallyhouse installer, which then asked for administrator rights. Now every click fails with:

```text
Error moving mouse: Simulate("not all input events were sent. they may have been blocked by UIPI")
```

I'm stepping away for an hour. Just have it keep retrying the click every minute until it goes through.
