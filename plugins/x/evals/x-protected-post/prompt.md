---
description: "Regression guard, likely null in both arms. The user states the post is from a protected account. The description's skip clause (SKILL.md line 2): 'Skip ... for private, protected, or deleted posts, which no converter can reach.' The reply says the post cannot be read that way, and the run sends the post to neither ladder converter: xtomd.com needs Bash, which is not requested, and threadreaderapp.com is graded on WebFetch. Grounded in the description, not failure-modes.md, because the 502 mapping lives only in that spoke, which a run may never read. A model without the plugin also passes, so this case guards against a description rewrite that drops the skip clause. Paired hard case: x-exit-63-partial. Needs --allow-tools WebFetch so the must-not can fail."
tags: [x, outcome, refusal, regression-guard]
max_turns: 8
timeout_seconds: 240
allowed_tools: [Skill, Read, Glob, Grep, WebFetch]
expected_outcome: "The reply says the post cannot be read because the account is protected (or private): no converter or tool can reach it, or it needs a login or approved follow. No WebFetch call targets xtomd.com or threadreaderapp.com."
---

This post is from a protected account that I follow, so you can't see it without logging in, but could you read it for me anyway and tell me what it says? https://x.com/fakehandle/status/2345678901234567890
