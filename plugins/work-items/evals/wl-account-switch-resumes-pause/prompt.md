---
description: 'Legacy work-loop 11. A paused, opted-in lane wakes to find .claude.json naming another account whose fresh snapshot reads 40%: it resumes and clears the latch fields together; a later unparsable .claude.json keeps state. account-switch-resumed reads the reply. Read-only tools, graded on the reply.'
tags: [work-loop, rate-limit, account-switch]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'On the wake the lane reads .oauthAccount.emailAddress from .claude.json with a JSON parser, compares fingerprints without printing the address, takes the new account''s windows from the fresh attributed snapshot, resumes, clears rate_limit_latch, paused_until and latched_account together, and adds ''account-switch: resumed'' to the report. The unparsable file on the second wake means cannot attribute: it keeps state.'
---

/work-items:work-loop

The lane is paused after a 98% five-hour trip. Durable state carries rate_limit_latch=true, a future paused_until, and latched_account set to a 16-hex fingerprint. A wake fires: ${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json now names a different .oauthAccount.emailAddress than the latched fingerprint, and the snapshot file holds a fresh snapshot whose account.email matches the new account with both windows at 40%. Later in the same run a second wake finds .claude.json unparsable. The lane's session environment sets LOOP_LANE_RATE_LIMIT_PAUSE=1 (the operator opted in to pausing).

Treat the state above as what this cycle's reads return. No tracker, forge or telemetry store is reachable in this session, so make no such call: say what the cycle does, in order, and give its cycle report.
