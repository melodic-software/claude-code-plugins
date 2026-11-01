---
description: "A pasted twitter.com share link with ?s= and &t= tracking tokens, after WebFetch hit a login wall: the description's trigger ('WebFetch returned a login wall on x.com', SKILL.md line 2) routes to x:read. The gate rebuilds the URL from its captures (lines 88-111), so the legacy host becomes x.com and the query string is never transmitted; step 1 POSTs the rebuilt URL to xtomd (lines 129-144). Graders read tool-call inputs only, so the case grades without a successful fetch. routes-x-read is a with-only indicator. uses-xtomd scores in both arms: a model without the plugin could reach the same converter, it just is not told to. The two no-token graders are behavior any model can pass. Needs --allow-tools Bash WebFetch so the must-not calls can fail."
tags: [x, outcome, routing, gate, egress]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash, WebFetch]
expected_outcome: "The run loads the x:read skill through a Skill call; a Bash call sends the rebuilt https://x.com/fakehandle/status/1234567890123456789 to xtomd.com/api/markdown or /api/fetch; no curl, wget or similar command and no WebFetch URL carries the AbCdEfGhIjKlMnOp tracking token."
---

I tried WebFetch on this link a friend shared and it only gave me a login wall: https://twitter.com/fakehandle/status/1234567890123456789?s=20&t=AbCdEfGhIjKlMnOp

What does the post actually say?
