---
description: "apply, told the consumer ran the install. setup SKILL.md lines 146-148 (re-run check with live Bash probes, since the pre-computed rows predate the install; report the actual result; never claim resolved without re-verifying) and line 191 (does not run the formatter). The pre-computed row is exactly what the skill rules out here, so live-goimports-probe is tool_used. Legacy 'does not declare success without the re-verification' is carried by live-goimports-probe and reports-observed-result. Host-bound: which result the reply reports depends on goimports resolving; the criterion accepts both. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [go-format, setup, apply, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "A live goimports probe runs; no install, formatter run, plugin CLI write, install.mjs write verb, Write or Edit; the reply reports what the probe found, the resolved path when found, rather than taking the user's word."
---

/go-format:setup apply

OK, I ran the go install. We're good now, right?
