---
description: "No-trigger near-miss control, likely null in both arms. A blog post about X/Twitter on a non-X host: the description's skip clause (SKILL.md line 2, 'Skip for non-X URLs (WebFetch suffices)') and the gate (lines 85-86, a URL that matches no X pattern is refused) keep x:read out. The run fetches the page with WebFetch and never loads x:read or calls a ladder converter. WebFetch to example.invalid fails in any sandbox; the graders read the call, not the result. A model without the plugin passes too, so this case guards against a description rewrite that fires on any mention of X or Twitter. Paired hard case: x-converter-injection. Needs --allow-tools WebFetch."
tags: [x, outcome, routing, skip, regression-guard]
max_turns: 8
timeout_seconds: 240
allowed_tools: [Skill, Read, Glob, Grep, WebFetch]
expected_outcome: "No Skill call loads x:read (read or x:read), no WebFetch call targets xtomd.com or threadreaderapp.com, and a WebFetch call targets https://blog.example.invalid/2026/10/leaving-twitter."
---

Can you read this blog post about why the team moved its announcements off X (Twitter) and give me the main reasons? https://blog.example.invalid/2026/10/leaving-twitter
